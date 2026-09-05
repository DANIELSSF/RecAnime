import Auth
import Foundation
@testable import RecAnimeKit
import Testing

@Suite("AuthErrorMapping")
struct AuthErrorMappingTests {
    private func apiFailure(_ code: ErrorCode, status: Int, message: String = "boom") -> AuthError {
        .api(
            message: message,
            errorCode: code,
            underlyingData: Data(),
            underlyingResponse: HTTPURLResponse(
                url: URL(string: "https://auth.example.test/auth/v1/token")!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }

    @Test("a missing session is unauthorized")
    func sessionMissing() {
        #expect(APIError.fromAuthFailure(AuthError.sessionMissing) == .unauthorized)
    }

    @Test("reuse detection on the refresh token is unauthorized")
    func refreshTokenAlreadyUsed() {
        #expect(APIError.fromAuthFailure(apiFailure(.refreshTokenAlreadyUsed, status: 400)) == .unauthorized)
        #expect(APIError.fromAuthFailure(apiFailure(.refreshTokenNotFound, status: 400)) == .unauthorized)
        // An unknown code with a 4xx status is still a dead session.
        #expect(APIError.fromAuthFailure(apiFailure(ErrorCode("something_else"), status: 401)) == .unauthorized)
    }

    @Test("a failing auth server is a retryable server error")
    func serverFailure() {
        #expect(
            APIError.fromAuthFailure(apiFailure(.unexpectedFailure, status: 500, message: "down"))
                == .server(status: 500, code: "unexpected_failure", message: "down")
        )
    }

    @Test("connectivity failures never become unauthorized")
    func connectivity() {
        #expect(APIError.fromAuthFailure(URLError(.timedOut)) == .network(code: URLError.timedOut.rawValue))
        #expect(APIError.fromAuthFailure(URLError(.cancelled)) == .cancelled)
        #expect(APIError.fromAuthFailure(CancellationError()) == .cancelled)
        #expect(APIError.fromAuthFailure(AuthError.implicitGrantRedirect(message: "x")) == .network(code: -1))
    }
}
