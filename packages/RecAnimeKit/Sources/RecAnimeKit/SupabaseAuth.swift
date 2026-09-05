import Auth
import Foundation
import RecAnimeCore

/// Builds Supabase Auth clients. Only the Auth product is used: the apps never talk to PostgREST.
public enum SupabaseAuthFactory {
    /// Persistent client for the device session (Keychain-backed, auto refreshing).
    public static func makeClient(url: URL, publishableKey: String, keychainService: String = Identifiers.keychainService) -> AuthClient {
        AuthClient(configuration: AuthClient.Configuration(
            url: url.appending(path: "auth/v1"),
            headers: ["apikey": publishableKey, "Authorization": "Bearer \(publishableKey)"],
            localStorage: KeychainLocalStorage(service: keychainService),
            autoRefreshToken: true
        ))
    }

    /// Throwaway client used by the iPhone to mint an independent session for the Watch.
    /// Never call `signOut` on it: that would revoke the session it just minted.
    public static func makeMinter(url: URL, publishableKey: String) -> AuthClient {
        AuthClient(configuration: AuthClient.Configuration(
            url: url.appending(path: "auth/v1"),
            headers: ["apikey": publishableKey, "Authorization": "Bearer \(publishableKey)"],
            storageKey: "recanime-watch-minter",
            localStorage: InMemoryAuthStorage(),
            autoRefreshToken: false
        ))
    }
}

/// Non-persistent storage for the minter client.
public final class InMemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    public init() {}

    public func store(key: String, value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }

    public func retrieve(key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    public func remove(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}

/// `TokenProvider` backed by a Supabase `AuthClient`.
public struct SupabaseTokenProvider: TokenProvider {
    private let auth: AuthClient

    public init(auth: AuthClient) {
        self.auth = auth
    }

    public func accessToken() async throws -> String {
        do {
            return try await auth.session.accessToken
        } catch {
            throw APIError.fromAuthFailure(error)
        }
    }

    public func forceRefresh() async throws -> String {
        do {
            return try await auth.refreshSession().accessToken
        } catch {
            throw APIError.fromAuthFailure(error)
        }
    }
}

/// Snapshot of the signed-in account used by the UI.
public struct AuthUser: Sendable, Equatable, Hashable {
    public var id: String
    public var email: String
    public var name: String?
    public var avatarURL: URL?

    public init(id: String, email: String, name: String? = nil, avatarURL: URL? = nil) {
        self.id = id
        self.email = email
        self.name = name
        self.avatarURL = avatarURL
    }

    init(session: Session) {
        let md = session.user.userMetadata
        self.init(
            id: session.user.id.uuidString.lowercased(),
            email: session.user.email ?? "",
            name: md["full_name"]?.stringValue ?? md["name"]?.stringValue,
            avatarURL: (md["avatar_url"]?.stringValue ?? md["picture"]?.stringValue).flatMap(URL.init(string:))
        )
    }
}

/// Values transferred to the Watch (see `WatchSession`).
public extension Session {
    var watchSession: WatchSession {
        WatchSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: expiresAt),
            userId: user.id.uuidString.lowercased(),
            email: user.email ?? "",
            mintedAt: .now
        )
    }
}
