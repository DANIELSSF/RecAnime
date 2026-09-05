import Auth
import Foundation
@testable import RecAnimeCore
@testable import RecAnimeKit
@testable import RecAnimeKitTesting
import Testing

/// Builds an unsigned JWT the SDK can read locally. `AuthClient.setSession` only inspects the
/// `exp` claim (via `JWT.decodePayload`) to decide whether it needs to refresh; it never verifies
/// the signature client-side, so the third segment can be anything non-empty.
private func makeAccessToken(sub: String, email: String, exp: Date = .distantFuture) -> String {
    func segment(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    let header = segment(["alg": "HS256", "typ": "JWT"])
    let payload = segment([
        "sub": sub,
        "exp": Int(exp.timeIntervalSince1970),
        "role": "authenticated",
        "aud": "authenticated",
        "email": email,
    ])
    return "\(header).\(payload).sig"
}

/// Fake transport for the Auth SDK's `fetch` closure: records every request and answers
/// `GET .../user` and `POST .../logout` without touching the network.
private final class FakeAuthTransport: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private var _logoutFailure: (any Error)?
    let userID: String
    let userEmail: String

    init(userID: String, userEmail: String) {
        self.userID = userID
        self.userEmail = userEmail
    }

    var requests: [URLRequest] {
        lock.withLock { _requests }
    }

    var logoutRequests: [URLRequest] {
        requests.filter { $0.url?.path.hasSuffix("/logout") == true }
    }

    /// Makes every subsequent `/logout` call throw this instead of answering.
    func failLogout(with error: any Error) {
        lock.withLock { _logoutFailure = error }
    }

    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock { _requests.append(request) }
        guard let path = request.url?.path else { throw URLError(.badURL) }
        if path.hasSuffix("/user") {
            let (response, data) = MockURLProtocol.json(200, userJSON, for: request)
            return (data, response)
        }
        if path.hasSuffix("/logout") {
            if let failure = lock.withLock({ _logoutFailure }) {
                throw failure
            }
            let (response, data) = MockURLProtocol.json(204, "", for: request)
            return (data, response)
        }
        throw URLError(.unsupportedURL)
    }

    private var userJSON: String {
        #"{"id":"\#(userID)","aud":"authenticated","email":"\#(userEmail)","created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z","app_metadata":{},"user_metadata":{},"identities":[]}"#
    }
}

@Suite("SessionStore")
@MainActor
struct SessionStoreTests {
    private func makeAuth(_ transport: FakeAuthTransport) -> AuthClient {
        AuthClient(configuration: AuthClient.Configuration(
            url: URL(string: "https://auth.example.test/auth/v1")!,
            localStorage: InMemoryAuthStorage(),
            fetch: { try await transport.fetch($0) },
            autoRefreshToken: false
        ))
    }

    /// Builds a `SessionStore` already `.signedIn`, adopting a session the way the Watch does.
    /// The access token is a real (unsigned) JWT with a far-future `exp`, so `setSession` resolves
    /// it without a token refresh — it only fetches `/user`, which `transport` stubs.
    private func makeSignedInStore(
        id: String = UUID().uuidString,
        email: String = "a@b.c"
    ) async throws -> (SessionStore, FakeAuthTransport) {
        let transport = FakeAuthTransport(userID: id, userEmail: email)
        let store = SessionStore(auth: makeAuth(transport))
        try await store.adopt(WatchSession(
            accessToken: makeAccessToken(sub: id, email: email),
            refreshToken: "refresh-1",
            expiresAt: .distantFuture,
            userId: id,
            email: email,
            mintedAt: .now
        ))
        return (store, transport)
    }

    @Test("invalidate is a no-op before signing in or after signing out")
    func invalidateNoOp() async {
        let transport = FakeAuthTransport(userID: UUID().uuidString, userEmail: "a@b.c")
        let store = SessionStore(auth: makeAuth(transport))

        // `.loading`: nothing has happened yet.
        await store.invalidate(message: "x")
        #expect(store.state == .loading)
        #expect(transport.requests.isEmpty)

        // `.signedOut`: there is no session to invalidate a second time.
        await store.signOut()
        #expect(store.state == .signedOut(message: nil))
        await store.invalidate(message: "x")
        #expect(store.state == .signedOut(message: nil))
        #expect(transport.requests.isEmpty)
    }

    @Test("invalidate signs out locally with a message and clears the session")
    func invalidateSignsOutLocally() async throws {
        let (store, transport) = try await makeSignedInStore()
        await store.invalidate(message: "x")
        #expect(store.state == .signedOut(message: "x"))
        #expect(transport.logoutRequests.count == 1)
        #expect(transport.logoutRequests.first?.url?.query == "scope=local")
        #expect(store.auth.currentSession == nil)
    }

    @Test("invalidate is idempotent: a second call sends no extra logout and keeps the first message")
    func invalidateIsIdempotent() async throws {
        let (store, transport) = try await makeSignedInStore()
        await store.invalidate(message: "first")
        await store.invalidate(message: "second")
        #expect(store.state == .signedOut(message: "first"))
        #expect(transport.logoutRequests.count == 1)
    }

    @Test("revoke maps each reason to its message; handleUnauthorized is the expired alias")
    func revokeMapsReasons() async throws {
        let (sessionExpiredStore, _) = try await makeSignedInStore()
        await sessionExpiredStore.revoke(.sessionExpired)
        #expect(sessionExpiredStore.state == .signedOut(message: SessionStore.expiredMessage))

        let (notAllowedStore, _) = try await makeSignedInStore()
        await notAllowedStore.revoke(.emailNotAllowed)
        #expect(notAllowedStore.state == .signedOut(message: SessionStore.notAllowedMessage))

        let (unauthorizedStore, _) = try await makeSignedInStore()
        await unauthorizedStore.handleUnauthorized()
        #expect(unauthorizedStore.state == .signedOut(message: SessionStore.expiredMessage))
    }

    @Test("the invalidation message survives the SDK's own .signedOut event")
    func messageSurvivesSignedOutEvent() async throws {
        let (store, _) = try await makeSignedInStore()
        store.bootstrap() // starts observing `auth.authStateChanges`, which also emits `.signedOut`.
        await store.invalidate(message: "x")
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(store.state == .signedOut(message: "x"))
    }

    @Test("adopt installs a signed-in session with the watch's identity")
    func adoptSetsSignedIn() async throws {
        let id = UUID().uuidString
        let (store, _) = try await makeSignedInStore(id: id, email: "watch@b.c")
        let user = try #require(store.user)
        #expect(user.email == "watch@b.c")
        #expect(user.id == id.lowercased())
        #expect(store.state == .signedIn(user))
    }

    @Test("signOut defaults to the global scope and clears the message")
    func signOutDefaultsToGlobalScope() async throws {
        let (store, transport) = try await makeSignedInStore()
        await store.signOut()
        #expect(store.state == .signedOut(message: nil))
        #expect(transport.logoutRequests.count == 1)
        #expect(transport.logoutRequests.first?.url?.query == "scope=global")
    }

    @Test("a logout network failure still leaves the store signed out (invalidate uses try?)")
    func invalidateSwallowsLogoutFailure() async throws {
        let (store, transport) = try await makeSignedInStore()
        // `.cancelled` is not in the SDK's retryable-error set, so this fails once instead of
        // being retried (with a real delay) by `RetryRequestInterceptor`.
        transport.failLogout(with: URLError(.cancelled))
        await store.invalidate(message: "x")
        #expect(store.state == .signedOut(message: "x"))
        #expect(store.auth.currentSession == nil)
    }
}
