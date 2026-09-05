import Foundation
@testable import RecAnimeCore
@testable import RecAnimeKit
@testable import RecAnimeKitTesting
import Testing

private struct BridgeTokenProvider: TokenProvider {
    let inner: StaticTokenProvider
    func accessToken() async throws -> String {
        try await inner.accessToken()
    }

    func forceRefresh() async throws -> String {
        try await inner.forceRefresh()
    }
}

/// Token provider that always fails; used to check how `APIClient` maps provider errors.
private struct FailingTokenProvider: TokenProvider {
    let failure: @Sendable () -> any Error

    func accessToken() async throws -> String {
        throw failure()
    }

    func forceRefresh() async throws -> String {
        throw failure()
    }
}

/// Collects the reasons passed to `onAccessRevoked`, which fires from a detached task.
private final class RevocationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var reasons: [AccessRevocation] = []

    var recorded: [AccessRevocation] {
        lock.withLock { reasons }
    }

    var handler: AccessRevokedHandler {
        { [self] reason in lock.withLock { reasons.append(reason) } }
    }

    /// Waits for the handler to fire, then returns what it recorded.
    func awaitReasons(count: Int = 1) async -> [AccessRevocation] {
        for _ in 0 ..< 100 {
            let current = recorded
            if current.count >= count {
                return current
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return recorded
    }

    /// Gives a handler that should never fire enough time to prove it did not.
    func awaitSilence() async -> [AccessRevocation] {
        try? await Task.sleep(for: .milliseconds(100))
        return recorded
    }
}

@Suite("APIClient", .serialized)
struct APIClientTests {
    let base = URL(string: "https://api.example.test")!

    func makeClient(onAccessRevoked: AccessRevokedHandler? = nil) -> (APIClient, StaticTokenProvider) {
        let tokens = StaticTokenProvider()
        let client = APIClient(
            baseURL: base,
            tokenProvider: BridgeTokenProvider(inner: tokens),
            session: MockURLProtocol.session(),
            onAccessRevoked: onAccessRevoked
        )
        return (client, tokens)
    }

    func makeClient(tokenProvider: any TokenProvider, onAccessRevoked: AccessRevokedHandler?) -> APIClient {
        APIClient(
            baseURL: base,
            tokenProvider: tokenProvider,
            session: MockURLProtocol.session(),
            onAccessRevoked: onAccessRevoked
        )
    }

    @Test("decodes the envelope and sends the bearer token")
    func decodesEnvelope() async throws {
        let (client, _) = makeClient()
        MockURLProtocol.setHandler { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
            #expect(request.url?.path == "/v1/me")
            return MockURLProtocol.json(
                200,
                #"{"data":{"id":"u1","email":"a@b.c","displayName":"A","avatarUrl":"","createdAt":"2026-08-24T10:00:00Z","settings":{"sfw":true,"timezone":"UTC"}}}"#,
                for: request
            )
        }
        let me: APIResponse<User> = try await client.send(.me)
        #expect(me.data.email == "a@b.c")
    }

    @Test("401 triggers exactly one refresh and a retry")
    func refreshOn401() async throws {
        let (client, tokens) = makeClient()
        MockURLProtocol.setHandler { request in
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1" {
                return MockURLProtocol.json(401, #"{"error":{"code":"unauthorized","message":"expired"}}"#, for: request)
            }
            return MockURLProtocol.json(200, #"{"data":{"sfw":false,"timezone":"UTC"}}"#, for: request)
        }
        let settings: APIResponse<Settings> = try await client.send(.updateSettings(SettingsPatch(sfw: false)))
        #expect(settings.data.sfw == false)
        #expect(tokens.refreshes == 1)

        MockURLProtocol.setHandler { request in MockURLProtocol.json(401, "{}", for: request) }
        await #expect(throws: APIError.unauthorized) {
            let _: APIResponse<User> = try await client.send(.me)
        }
    }

    @Test("server errors carry the API error code; 204 works for deletes")
    func serverErrorsAndNoContent() async throws {
        let (client, _) = makeClient()
        MockURLProtocol.setHandler { request in
            MockURLProtocol.json(400, #"{"error":{"code":"validation_error","message":"q too short","requestId":"r1"}}"#, for: request)
        }
        await #expect(throws: APIError.server(status: 400, code: "validation_error", message: "q too short")) {
            let _: APIResponse<[AnimeSummary]> = try await client.send(.search("ab"))
        }
        MockURLProtocol.setHandler { request in
            #expect(request.httpMethod == "DELETE")
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }
        try await client.sendNoContent(.deleteLibrary(1))
    }

    @Test("query building drops empty values and encodes bodies")
    func endpoints() throws {
        let req = Endpoint.top(filter: nil, type: "tv", page: 2).request(baseURL: base)
        #expect(req.url?.absoluteString == "https://api.example.test/v1/top?type=tv&page=2")
        let first = Endpoint.seasonNow(page: 1).request(baseURL: base)
        #expect(first.url?.query == nil)
        let put = Endpoint.upsertLibrary(5, LibraryPatch(status: .watching, episodesWatched: 3)).request(baseURL: base)
        let body = try JSONSerialization.jsonObject(with: #require(put.httpBody)) as? [String: Any]
        #expect(body?["status"] as? String == "watching")
        #expect(body?["episodesWatched"] as? Int == 3)
        #expect(body?["favorite"] == nil)
        #expect(put.httpMethod == "PUT")
    }

    @Test("a token provider that reports a dead session revokes access")
    func providerUnauthorizedRevokes() async {
        let recorder = RevocationRecorder()
        let client = makeClient(
            tokenProvider: FailingTokenProvider { APIError.unauthorized },
            onAccessRevoked: recorder.handler
        )
        MockURLProtocol.setHandler { request in MockURLProtocol.json(200, #"{"data":{}}"#, for: request) }
        await #expect(throws: APIError.unauthorized) {
            let _: APIResponse<User> = try await client.send(.me)
        }
        #expect(await recorder.awaitReasons() == [.sessionExpired])
    }

    @Test("being offline never signs the user out")
    func providerOfflineKeepsSession() async {
        let recorder = RevocationRecorder()
        let client = makeClient(
            tokenProvider: FailingTokenProvider { URLError(.notConnectedToInternet) },
            onAccessRevoked: recorder.handler
        )
        MockURLProtocol.setHandler { request in MockURLProtocol.json(200, #"{"data":{}}"#, for: request) }
        await #expect(throws: APIError.network(code: URLError.notConnectedToInternet.rawValue)) {
            let _: APIResponse<User> = try await client.send(.me)
        }
        #expect(await recorder.awaitSilence().isEmpty)
    }

    @Test("a 401 that survives the refresh revokes access")
    func persistent401Revokes() async {
        let recorder = RevocationRecorder()
        let (client, tokens) = makeClient(onAccessRevoked: recorder.handler)
        MockURLProtocol.setHandler { request in MockURLProtocol.json(401, #"{"error":{"code":"unauthorized"}}"#, for: request) }
        await #expect(throws: APIError.unauthorized) {
            let _: APIResponse<User> = try await client.send(.me)
        }
        #expect(tokens.refreshes == 1)
        #expect(await recorder.awaitReasons() == [.sessionExpired])
    }

    @Test("403 email_not_allowed revokes access and still throws the server error")
    func emailNotAllowedRevokes() async {
        let recorder = RevocationRecorder()
        let (client, _) = makeClient(onAccessRevoked: recorder.handler)
        MockURLProtocol.setHandler { request in
            MockURLProtocol.json(403, #"{"error":{"code":"email_not_allowed","message":"no"}}"#, for: request)
        }
        await #expect(throws: APIError.server(status: 403, code: "email_not_allowed", message: "no")) {
            let _: APIResponse<User> = try await client.send(.me)
        }
        #expect(await recorder.awaitReasons() == [.emailNotAllowed])
    }

    @Test("another 403 leaves the session alone")
    func otherForbiddenKeepsSession() async {
        let recorder = RevocationRecorder()
        let (client, _) = makeClient(onAccessRevoked: recorder.handler)
        MockURLProtocol.setHandler { request in
            MockURLProtocol.json(403, #"{"error":{"code":"forbidden","message":"no"}}"#, for: request)
        }
        await #expect(throws: APIError.server(status: 403, code: "forbidden", message: "no")) {
            let _: APIResponse<User> = try await client.send(.me)
        }
        #expect(await recorder.awaitSilence().isEmpty)
    }

    @Test("a 403 without a body never touches the session")
    func forbiddenWithoutBodyKeepsSession() async {
        let recorder = RevocationRecorder()
        let (client, _) = makeClient(onAccessRevoked: recorder.handler)
        MockURLProtocol.setHandler { request in
            (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!, Data())
        }
        await #expect(throws: APIError.server(status: 403, code: nil, message: nil)) {
            let _: APIResponse<User> = try await client.send(.me)
        }
        #expect(await recorder.awaitSilence().isEmpty)
    }

    @Test("a 500 never touches the session")
    func serverErrorKeepsSession() async {
        let recorder = RevocationRecorder()
        let (client, _) = makeClient(onAccessRevoked: recorder.handler)
        MockURLProtocol.setHandler { request in
            (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }
        await #expect(throws: APIError.server(status: 500, code: nil, message: nil)) {
            let _: APIResponse<User> = try await client.send(.me)
        }
        #expect(await recorder.awaitSilence().isEmpty)
    }
}
