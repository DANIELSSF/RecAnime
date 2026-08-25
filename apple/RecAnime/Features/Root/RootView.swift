import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// Chooses between login, the main shell, and the unconfigured/dev states.
struct RootView: View {
    @Environment(AppDependencies.self) private var deps

    var body: some View {
        if let session = deps.session {
            SessionGate(session: session)
        } else {
            #if DEBUG
                MainTabView()
            #else
                EmptyStateView(
                    title: "Configuración incompleta",
                    message: "Falta Secrets.xcconfig con la URL y la clave de Supabase.",
                    systemImage: "gearshape.2"
                )
            #endif
        }
    }
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
        .animation(.snappy, value: session.state)
    }
}
