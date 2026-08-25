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
                HStack(spacing: isInline ? Theme.Spacing.s : Theme.Spacing.m) {
                    PosterImage(url: item.anime.imageURL, width: isInline ? 32 : 36, height: isInline ? 32 : 36, cornerRadius: Theme.Radius.thumb)
                    if isInline {
                        // Minimized tab bar: poster · (title over progress) · +
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.anime.title)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                            Text(progressText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("VIENDO AHORA")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Text(item.anime.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text("· \(progressText)")
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
            .accessibilityLabel("\(item.anime.title), \(progressText)")
            Button {
                library.increment(for: item.anime)
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Theme.accentSoft, in: Circle().inset(by: isInline ? 7 : 4))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.increase, trigger: item.entry.episodesWatched)
            .accessibilityIdentifier("nowWatching.increment")
            .accessibilityLabel("Marcar episodio visto")
        }
        .padding(.leading, isInline ? Theme.Spacing.s : Theme.Spacing.m)
        .padding(.trailing, Theme.Spacing.xs)
        .accessibilityElement(children: .contain)
    }

    private var isInline: Bool {
        placement == .inline
    }

    private var progressText: String {
        if let total = item.progress.episodesTotal {
            return "ep \(item.entry.episodesWatched)/\(total)"
        }
        return "ep \(item.entry.episodesWatched)"
    }
}
