import GoogleSignIn
import UIKit

/// Wraps the Google Sign-In SDK: presents the sheet and returns the tokens Supabase needs.
@MainActor
enum GoogleSignInCoordinator {
    enum SignInError: LocalizedError {
        case notConfigured
        case noPresenter
        case missingIDToken

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Falta configurar el cliente de Google (Secrets.xcconfig)."
            case .noPresenter: "No se encontró una ventana para presentar el inicio de sesión."
            case .missingIDToken: "Google no devolvió un ID token."
            }
        }
    }

    struct Tokens: Sendable {
        let idToken: String
        let accessToken: String
    }

    static var isConfigured: Bool {
        !((Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String) ?? "").isEmpty
    }

    static func signIn() async throws -> Tokens {
        guard isConfigured else { throw SignInError.notConfigured }
        guard let presenter = presentingViewController() else { throw SignInError.noPresenter }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idToken = result.user.idToken?.tokenString else { throw SignInError.missingIDToken }
        return Tokens(idToken: idToken, accessToken: result.user.accessToken.tokenString)
    }

    /// Fresh tokens for a silent re-mint (Watch session) when the user previously signed in.
    static func refreshedTokens() async throws -> Tokens {
        guard isConfigured else { throw SignInError.notConfigured }
        let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
        let refreshed = try await user.refreshTokensIfNeeded()
        guard let idToken = refreshed.idToken?.tokenString else { throw SignInError.missingIDToken }
        return Tokens(idToken: idToken, accessToken: refreshed.accessToken.tokenString)
    }

    static func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    @discardableResult
    static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    private static func presentingViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard var controller = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return nil }
        while let presented = controller.presentedViewController {
            controller = presented
        }
        return controller
    }
}
