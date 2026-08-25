import RecAnimeCore
import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// "Viendo ahora" mini bar inside the tab bar's bottom accessory (like Music's mini player).
struct NowWatchingBar: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(Router.self) private var router
    @Environment(LibraryStore.self) private var library
    let item: RecAnimeCore.LibraryItem

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button {
                router.open(anime: item.anime.malId)
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    PosterImage(url: item.anime.imageURL, width: 36, height: 36, cornerRadius: Theme.Radius.thumb)
                    VStack(alignment: .leading, spacing: 1) {
                        if placement != .inline {
                            Text("VIENDO AHORA")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Text(item.anime.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(progressText).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                                .contentTransition(.numericText())
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            Button {
                library.increment(for: item.anime)
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(Theme.accentSoft, in: Circle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.increase, trigger: item.entry.episodesWatched)
            .accessibilityLabel("Marcar episodio visto")
        }
        .padding(.horizontal, Theme.Spacing.m)
        .accessibilityElement(children: .contain)
    }

    private var progressText: String {
        if let total = item.progress.episodesTotal {
            return "· ep \(item.entry.episodesWatched)/\(total)"
        }
        return "· ep \(item.entry.episodesWatched)"
    }
}
