import Auth
import Foundation
import Observation
import RecAnimeCore

/// Owns the Supabase session on a device and exposes it to the UI.
@MainActor
@Observable
public final class SessionStore {
    public enum State: Equatable, Sendable {
        case loading
        case signedOut(message: String?)
        case signedIn(AuthUser)
    }

    public static let expiredMessage = "Tu sesión ha caducado. Inicia sesión de nuevo."
    public static let notAllowedMessage = "Esta cuenta no está autorizada para usar RecAnime."

    public private(set) var state: State = .loading
    public let auth: AuthClient
    public let tokenProvider: any TokenProvider
    private var observer: Task<Void, Never>?

    public init(auth: AuthClient) {
        self.auth = auth
        tokenProvider = SupabaseTokenProvider(auth: auth)
    }

    /// Resolves the persisted session and keeps following auth changes.
    public func bootstrap() {
        guard observer == nil else { return }
        if let session = auth.currentSession {
            state = .signedIn(AuthUser(session: session))
        }
        observer = Task { [weak self, auth] in
            for await change in auth.authStateChanges {
                guard let self else { return }
                switch change.event {
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    if let session = change.session {
                        state = .signedIn(AuthUser(session: session))
                    } else if case .loading = state {
                        state = .signedOut(message: nil)
                    }
                case .signedOut:
                    if case .signedIn = state {
                        state = .signedOut(message: nil)
                    }
                    if case .loading = state {
                        state = .signedOut(message: nil)
                    }
                default:
                    break
                }
            }
        }
    }

    /// Exchanges a Google ID token for a Supabase session.
    public func signInWithGoogle(idToken: String, accessToken: String?) async throws -> Session {
        let session = try await auth.signInWithIdToken(credentials: OpenIDConnectCredentials(
            provider: .google,
            idToken: idToken,
            accessToken: accessToken
        ))
        state = .signedIn(AuthUser(session: session))
        return session
    }

    /// Installs a session received from the iPhone (Watch).
    public func adopt(_ watchSession: WatchSession) async throws {
        let session = try await auth.setSession(accessToken: watchSession.accessToken, refreshToken: watchSession.refreshToken)
        state = .signedIn(AuthUser(session: session))
    }

    /// Signs out everywhere (`.global` also revokes the Watch session).
    public func signOut(scope: SignOutScope = .global) async {
        try? await auth.signOut(scope: scope)
        state = .signedOut(message: nil)
    }

    /// Local sign-out with a reason shown on the login screen. No-op when already signed out.
    public func invalidate(message: String) async {
        guard case .signedIn = state else { return }
        // `.local` only drops the device session; the SDK emits `.signedOut` before the network call,
        // so the message is written last and survives that event.
        try? await auth.signOut(scope: .local)
        // A sign-in that completed while this call was suspended left a new session behind: keep it.
        guard auth.currentSession == nil else { return }
        state = .signedOut(message: message)
    }

    /// Turns a revocation reported by `APIClient` into the matching local sign-out.
    public func revoke(_ reason: AccessRevocation) async {
        switch reason {
        case .sessionExpired:
            await invalidate(message: Self.expiredMessage)
        case .emailNotAllowed:
            await invalidate(message: Self.notAllowedMessage)
        }
    }

    /// Called when the API keeps answering 401 after a refresh: the session is gone.
    public func handleUnauthorized() async {
        await invalidate(message: Self.expiredMessage)
    }

    public var user: AuthUser? {
        if case let .signedIn(user) = state {
            return user
        }
        return nil
    }
}
