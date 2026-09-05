import Auth
import Foundation

/// Server codes that mean the stored Supabase session can never work again: the user must sign in.
private let revokedSessionCodes: Set<ErrorCode> = [
    .refreshTokenNotFound,
    .refreshTokenAlreadyUsed,
    .sessionNotFound,
    .sessionExpired,
    .userNotFound,
    .userBanned,
    .badJWT,
    .invalidCredentials,
]

public extension APIError {
    /// Maps a Supabase Auth failure to the API error the UI understands.
    static func fromAuthFailure(_ error: any Error) -> APIError {
        switch error {
        case let error as AuthError:
            return fromAuthError(error)
        case let error as URLError where error.code == .cancelled:
            return .cancelled
        case let error as URLError:
            return .network(code: error.errorCode)
        case is CancellationError:
            return .cancelled
        default:
            return .network(code: -1)
        }
    }

    private static func fromAuthError(_ error: AuthError) -> APIError {
        switch error {
        case .sessionMissing:
            return .unauthorized
        case let .api(message, errorCode, _, response):
            // 4xx from the token endpoint means the credentials are dead; 5xx is the server's problem.
            if revokedSessionCodes.contains(errorCode) || [400, 401, 403].contains(response.statusCode) {
                return .unauthorized
            }
            return .server(status: response.statusCode, code: errorCode.rawValue, message: message)
        default:
            return .network(code: -1)
        }
    }
}
