import Foundation
import RecAnimeCore

/// Supplies bearer tokens; the implementation refreshes them when expired.
public protocol TokenProvider: Sendable {
    /// A currently valid access token.
    func accessToken() async throws -> String
    /// Forces a refresh (used exactly once after a 401) and returns the new token.
    func forceRefresh() async throws -> String
}

/// Errors surfaced to the UI layer.
public enum APIError: Error, Sendable, Equatable {
    case unauthorized
    case network(code: Int)
    case server(status: Int, code: String?, message: String?)
    case decoding(String)
    case cancelled
    case invalidResponse

    /// Whether a retry button makes sense.
    public var isRetryable: Bool {
        switch self {
        case .network, .invalidResponse: true
        case let .server(status, _, _): status >= 500
        default: false
        }
    }
}

/// Why the device lost access to the API.
public enum AccessRevocation: Sendable, Equatable {
    /// The token provider says the session is gone, or a 401 persisted after one refresh.
    case sessionExpired
    /// The server answered 403 with code "email_not_allowed".
    case emailNotAllowed
}

/// Notified once access is lost. Implementations must be idempotent: the same reason can arrive twice.
public typealias AccessRevokedHandler = @Sendable (AccessRevocation) async -> Void

/// Decoded envelope.
public struct APIResponse<T: Sendable>: Sendable {
    public var data: T
    public var meta: Meta?
    public var pagination: Pagination?

    public init(data: T, meta: Meta? = nil, pagination: Pagination? = nil) {
        self.data = data
        self.meta = meta
        self.pagination = pagination
    }
}

/// JSON client for the RecAnime API. One instance per process; safe to share.
public actor APIClient {
    public let baseURL: URL
    private let tokenProvider: any TokenProvider
    private let session: URLSession
    private let onAccessRevoked: AccessRevokedHandler?
    private let decoder = JSONDecoder.recanime

    public init(
        baseURL: URL,
        tokenProvider: any TokenProvider,
        session: URLSession = .shared,
        onAccessRevoked: AccessRevokedHandler? = nil
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
        self.onAccessRevoked = onAccessRevoked
    }

    /// Sends the request and decodes the `{data, meta, pagination}` envelope.
    public func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> APIResponse<T> {
        let (data, response) = try await perform(endpoint)
        if response.statusCode == 204 || data.isEmpty {
            throw APIError.invalidResponse
        }
        do {
            let env = try decoder.decode(Envelope<T>.self, from: data)
            return APIResponse(data: env.data, meta: env.meta, pagination: env.pagination)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Sends a request whose success has no body (DELETE → 204).
    public func sendNoContent(_ endpoint: Endpoint) async throws {
        _ = try await perform(endpoint)
    }

    private func perform(_ endpoint: Endpoint) async throws -> (Data, HTTPURLResponse) {
        var token = try await fetchToken { try await tokenProvider.accessToken() }
        var (data, response) = try await execute(endpoint, token: token)
        if response.statusCode == 401 {
            token = try await fetchToken { try await tokenProvider.forceRefresh() }
            (data, response) = try await execute(endpoint, token: token)
            if response.statusCode == 401 {
                // One refresh was not enough: the session is gone.
                revoke(.sessionExpired)
                throw APIError.unauthorized
            }
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            let body = try? decoder.decode(APIErrorBody.self, from: data)
            if response.statusCode == 403, body?.error.code == "email_not_allowed" {
                revoke(.emailNotAllowed)
            }
            throw APIError.server(status: response.statusCode, code: body?.error.code, message: body?.error.message)
        }
        return (data, response)
    }

    /// Runs a token-provider call and normalises its failure. An unknown error never becomes
    /// `.unauthorized`: being offline must not sign the user out.
    private func fetchToken(_ fetch: () async throws -> String) async throws -> String {
        do {
            return try await fetch()
        } catch let error as APIError {
            if error == .unauthorized {
                revoke(.sessionExpired)
            }
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw APIError.cancelled
        } catch let error as URLError {
            throw APIError.network(code: error.errorCode)
        } catch is CancellationError {
            throw APIError.cancelled
        } catch {
            throw APIError.network(code: -1)
        }
    }

    /// Fires the revocation handler without blocking the request that discovered the problem.
    private func revoke(_ reason: AccessRevocation) {
        guard let onAccessRevoked else { return }
        Task { await onAccessRevoked(reason) }
    }

    private func execute(_ endpoint: Endpoint, token: String) async throws -> (Data, HTTPURLResponse) {
        var request = endpoint.request(baseURL: baseURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            return (data, http)
        } catch let error as APIError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw APIError.cancelled
        } catch let error as URLError {
            throw APIError.network(code: error.errorCode)
        } catch is CancellationError {
            throw APIError.cancelled
        } catch {
            throw APIError.network(code: -1)
        }
    }
}
