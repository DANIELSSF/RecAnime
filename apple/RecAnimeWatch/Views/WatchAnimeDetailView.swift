import RecAnimeCore
import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// Progress gauge with "Episodio visto" / "Deshacer" glass buttons.
struct WatchAnimeDetailView: View {
    @Environment(WatchDependencies.self) private var deps
    @Environment(LibraryStore.self) private var library
    let malID: Int

    private var item: RecAnimeCore.LibraryItem? {
        library.items[malID]
    }

    var body: some View {
        if let item {
            ScrollView {
                VStack(spacing: 12) {
                    Gauge(
                        value: Double(item.entry.episodesWatched),
                        in: 0 ... Double(max(item.progress.episodesTotal ?? max(item.entry.episodesWatched, 1), 1))
                    ) {
                        EmptyView()
                    } currentValueLabel: {
                        VStack(spacing: 0) {
                            Text("\(item.entry.episodesWatched)").font(.title3.weight(.bold)).monospacedDigit().contentTransition(.numericText())
                            if let total = item.progress.episodesTotal {
                                Text("de \(total)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(Theme.progressGradient)
                    .scaleEffect(1.5)
                    .padding(.vertical, 18)
                    if let total = item.progress.episodesTotal, item.entry.episodesWatched >= total {
                        Text("Temporada completa").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Button {
                            Task { await deps.markEpisode(item, delta: 1) }
                        } label: {
                            Label("Episodio visto", systemImage: "plus").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.accent)
                        .controlSize(.large)
                    }
                    Button("Deshacer") { Task { await deps.markEpisode(item, delta: -1) } }
                        .buttonStyle(.glass)
                        .disabled(item.entry.episodesWatched == 0)
                    if let error = deps.lastError {
                        Text(error).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 6)
            }
            .navigationTitle(item.anime.title)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Sin datos", systemImage: "bookmark")
        }
    }
}
