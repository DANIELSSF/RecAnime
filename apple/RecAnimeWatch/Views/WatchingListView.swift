import RecAnimeCore
import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// "Viendo" list with progress.
struct WatchingListView: View {
    @Environment(WatchDependencies.self) private var deps
    @Environment(LibraryStore.self) private var library

    var body: some View {
        List {
            ForEach(library.groups.watching) { item in
                NavigationLink(value: item.anime.malId) {
                    HStack(spacing: 10) {
                        PosterImage(url: item.anime.imageURL, width: 40, height: 60, cornerRadius: Theme.Radius.thumb)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.anime.title).font(.footnote.weight(.semibold)).lineLimit(2)
                            HStack(spacing: 6) {
                                ProgressPill(watched: item.entry.episodesWatched, total: item.progress.episodesTotal)
                                if deps.outbox.isPending(item.anime.malId) {
                                    Image(systemName: "clock.arrow.circlepath").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            if let error = deps.lastError {
                Text(error).font(.footnote).foregroundStyle(.secondary).listRowBackground(Color.clear)
            } else if let last = deps.lastRefresh {
                Text("Actualizado \(last, style: .relative)").font(.footnote).foregroundStyle(.tertiary).listRowBackground(Color.clear)
            }
        }
        .overlay {
            if library.groups.watching.isEmpty {
                if library.isLoading {
                    ProgressView()
                } else {
                    ContentUnavailableView(
                        "Nada en Viendo",
                        systemImage: "bookmark",
                        description: Text("Marca una serie como Viendo desde el iPhone.")
                    )
                }
            }
        }
        .navigationTitle("Viendo")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Actualizar", systemImage: "arrow.clockwise") { Task { await deps.refresh(throttle: false) } }
            }
        }
        .task { await deps.refresh(throttle: true) }
    }
}
