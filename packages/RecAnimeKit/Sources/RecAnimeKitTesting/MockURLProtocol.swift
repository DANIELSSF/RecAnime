import Foundation

/// URLProtocol that answers from a handler; use `MockURLProtocol.session()` in tests.
public final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    public typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private nonisolated(unsafe) static var handler: Handler?

    public static func setHandler(_ handler: Handler?) {
        lock.lock(); defer { lock.unlock() }
        Self.handler = handler
    }

    public static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// JSON response helper.
    public static func json(_ status: Int, _ body: String, for request: URLRequest) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    override public class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override public class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override public func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            var request = request
            // URLSession strips httpBody into a stream; restore it for handlers that inspect bodies.
            if request.httpBody == nil, let stream = request.httpBodyStream {
                stream.open()
                var data = Data()
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let read = stream.read(buffer, maxLength: 4096)
                    if read <= 0 {
                        break
                    }
                    data.append(buffer, count: read)
                }
                stream.close()
                request.httpBody = data
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override public func stopLoading() {}
}

/// Token provider for tests: counts refreshes.
public final class StaticTokenProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var token: String
    public private(set) var refreshes = 0

    public init(token: String = "token-1") {
        self.token = token
    }

    public var current: String {
        lock.withLock { token }
    }
}

extension StaticTokenProvider: RecAnimeKitTokenProviding {
    public func accessToken() async throws -> String {
        current
    }

    public func forceRefresh() async throws -> String {
        rotate()
    }

    private func rotate() -> String {
        lock.withLock {
            refreshes += 1
            token = "token-\(refreshes + 1)"
            return token
        }
    }
}

/// Mirrors RecAnimeKit.TokenProvider without importing it here (keeps this target UI-free).
public protocol RecAnimeKitTokenProviding: Sendable {
    func accessToken() async throws -> String
    func forceRefresh() async throws -> String
}
