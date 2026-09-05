import RecAnimeKit
import RecAnimeUI
import SwiftUI

struct WatchRootView: View {
    @Environment(WatchDependencies.self) private var deps

    var body: some View {
        // No SessionStore means a dev-bypass build: the API needs no credentials.
        if deps.session == nil {
            WatchingListView()
        } else {
            switch deps.session?.state {
            case .signedIn:
                WatchingListView()
            case .loading:
                ProgressView("Cargando…")
                    .navigationTitle("RecAnime")
            default:
                NotSignedInView()
            }
        }
    }
}

struct NotSignedInView: View {
    @Environment(WatchDependencies.self) private var deps

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.largeTitle)
                .foregroundStyle(Theme.accent)
            Text("Abre RecAnime en tu iPhone para sincronizar tu sesión.")
                .font(.footnote)
                .multilineTextAlignment(.center)
            if let error = deps.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Reintentar") { deps.connectivity.requestSession() }
                .buttonStyle(.glass)
        }
        .padding()
        .navigationTitle("RecAnime")
        .task { deps.connectivity.requestSession() }
    }
}
