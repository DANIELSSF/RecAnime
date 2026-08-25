import RecAnimeCore
import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// "Viendo ahora" mini bar inside the tab bar's bottom accessory (like Music's mini player).
struct NowWatchingBar: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(AppDependencies.self) private var deps
    @Environment(Router.self) private var router
    @Environment(LibraryStore.self) private var library
    let item: RecAnimeCore.LibraryItem

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button {
                deps.summaries.remember(item.anime)
                router.open(anime: item.anime.malId)
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    if placement != .inline {
                        PosterImage(url: item.anime.imageURL, width: 36, height: 36, cornerRadius: Theme.Radius.thumb)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        if placement != .inline {
                            Text("VIENDO AHORA")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Text(item.anime.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if placement != .inline {
                                Text(progressText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                    .layoutPriority(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("nowWatching.open")
            .accessibilityLabel(placement == .inline ? "\(item.anime.title), \(progressText)" : item.anime.title)
            Button {
                library.increment(for: item.anime)
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Theme.accentSoft, in: Circle().inset(by: placement == .inline ? 7 : 4))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.increase, trigger: item.entry.episodesWatched)
            .accessibilityIdentifier("nowWatching.increment")
            .accessibilityLabel("Marcar episodio visto")
        }
        .padding(.leading, placement == .inline ? Theme.Spacing.s : Theme.Spacing.m)
        .padding(.trailing, Theme.Spacing.xs)
        .accessibilityElement(children: .contain)
    }

    private var progressText: String {
        if let total = item.progress.episodesTotal {
            return "· ep \(item.entry.episodesWatched)/\(total)"
        }
        return "· ep \(item.entry.episodesWatched)"
    }
}
