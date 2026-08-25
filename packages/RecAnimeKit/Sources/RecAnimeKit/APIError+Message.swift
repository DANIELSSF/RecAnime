import Foundation

public extension APIError {
    /// Spanish, user-facing message.
    var userMessage: String {
        switch self {
        case .unauthorized: "Tu sesión ha caducado."
        case .network:
            #if DEBUG
                "Sin conexión con el servidor. ¿Está corriendo `pnpm api:dev` en el Mac?"
            #else
                "Sin conexión con el servidor."
            #endif
        case let .server(status, code, _):
            switch code {
            case "upstream_rate_limited": "MyAnimeList está limitando las peticiones. Intenta en unos segundos."
            case "upstream_unavailable": "MyAnimeList no responde ahora mismo."
            case "not_found": "No encontramos ese anime."
            case "email_not_allowed": "Esta cuenta no está autorizada."
            default: status >= 500 ? "El servidor tuvo un problema." : "Petición inválida."
            }
        case .decoding: "Respuesta inesperada del servidor."
        case .cancelled: "Cancelado."
        case .invalidResponse: "Respuesta inválida del servidor."
        }
    }
}
