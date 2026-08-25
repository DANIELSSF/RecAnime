import RecAnimeKit
import RecAnimeUI
import SwiftUI

struct WatchRootView: View {
    @Environment(WatchDependencies.self) private var deps

    var body: some View {
        if deps.canUseAPI {
            WatchingListView()
        } else {
            NotSignedInView()
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
            Button("Reintentar") { deps.connectivity.requestSession() }
                .buttonStyle(.glass)
        }
        .padding()
        .navigationTitle("RecAnime")
        .task { deps.connectivity.requestSession() }
    }
}
