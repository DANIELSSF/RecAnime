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
    private let decoder = JSONDecoder.recanime

    public init(baseURL: URL, tokenProvider: any TokenProvider, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
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
        var token = try await tokenProvider.accessToken()
        var (data, response) = try await execute(endpoint, token: token)
        if response.statusCode == 401 {
            token = try await tokenProvider.forceRefresh()
            (data, response) = try await execute(endpoint, token: token)
            if response.statusCode == 401 {
                throw APIError.unauthorized
            }
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            let body = try? decoder.decode(APIErrorBody.self, from: data)
            throw APIError.server(status: response.statusCode, code: body?.error.code, message: body?.error.message)
        }
        return (data, response)
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
