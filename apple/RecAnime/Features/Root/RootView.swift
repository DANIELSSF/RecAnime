import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// Chooses between login, the main shell, and the unconfigured/dev states.
struct RootView: View {
    @Environment(AppDependencies.self) private var deps

    var body: some View {
        #if DEBUG
            if let session = deps.session {
                SessionGate(session: session)
            } else {
                MainTabView()
            }
        #else
            // A Release sideload with a missing API URL used to fall back to localhost and fail
            // with "Sin conexión"; name the missing piece instead.
            if let session = deps.session, deps.config.isAPIConfigured {
                SessionGate(session: session)
            } else {
                EmptyStateView(
                    title: "Configuración incompleta",
                    message: missingConfiguration,
                    systemImage: "gearshape.2"
                )
            }
        #endif
    }

    #if !DEBUG
        /// Supabase first: without it there is no session at all, whatever the API URL says.
        private var missingConfiguration: LocalizedStringKey {
            if deps.session == nil {
                return deps.config.isAPIConfigured
                    ? "Falta Secrets.xcconfig con la URL y la clave de Supabase."
                    : "Falta Secrets.xcconfig: URL y clave de Supabase, y la URL de la API (API_BASE_URL_RELEASE)."
            }
            return "Falta la URL de la API (API_BASE_URL_RELEASE en Secrets.xcconfig)."
        }
    #endif
}

private struct SessionGate: View {
    @Bindable var session: SessionStore

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ProgressView().controlSize(.large)
            case let .signedOut(message):
                LoginView(message: message)
            case .signedIn:
                MainTabView()
            }
        }
        .task { session.bootstrap() }
        .onChange(of: session.state, initial: false) { _, state in
            if case .signedOut = state {
                AppDependencies.shared.notifications.cancelAll()
                AppDependencies.shared.watchSync.sendSignedOut()
            }
        }
        .animation(.snappy, value: session.state)
    }
}
