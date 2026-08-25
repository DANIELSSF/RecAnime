import RecAnimeCore
import RecAnimeUI
import SwiftUI
import WidgetKit

/// "Próximo episodio" complication fed by the App Group snapshot the Watch app writes.
struct NextEpisodeEntry: TimelineEntry {
    let date: Date
    let item: ComplicationSnapshot.Item?

    static let placeholder = NextEpisodeEntry(date: .now, item: ComplicationSnapshot.Item(
        malID: 59978, title: "Frieren 2nd Season", nextEpisode: 8, nextAiringAt: .now.addingTimeInterval(2 * 3600), episodesWatched: 7,
        episodesTotal: 24
    ))
}

struct NextEpisodeProvider: TimelineProvider {
    private let store = AppGroupStore()

    func placeholder(in context: Context) -> NextEpisodeEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (NextEpisodeEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        let items = store.read(ComplicationSnapshot.self, file: AppGroupStore.complicationFile)?.items ?? []
        completion(NextEpisodeEntry(date: .now, item: upcoming(items, at: .now).first))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<NextEpisodeEntry>) -> Void) {
        let items = store.read(ComplicationSnapshot.self, file: AppGroupStore.complicationFile)?.items ?? []
        let now = Date.now
        var entries = [NextEpisodeEntry(date: now, item: upcoming(items, at: now).first)]
        // One entry per airing boundary: as an episode airs, the following one becomes "next".
        for airing in items.compactMap(\.nextAiringAt).filter({ $0 > now }).sorted().prefix(20) {
            let after = airing.addingTimeInterval(60)
            entries.append(NextEpisodeEntry(date: after, item: upcoming(items, at: after).first))
        }
        let policy: TimelineReloadPolicy = entries.count > 1 ? .after(entries[1].date) : .atEnd
        completion(Timeline(entries: entries, policy: policy))
    }

    /// Items whose next airing is still ahead of `date`, soonest first.
    private func upcoming(_ items: [ComplicationSnapshot.Item], at date: Date) -> [ComplicationSnapshot.Item] {
        items.filter { ($0.nextAiringAt ?? .distantPast) > date }.sorted { ($0.nextAiringAt ?? .distantFuture) < ($1.nextAiringAt ?? .distantFuture) }
    }
}

struct NextEpisodeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Identifiers.nextEpisodeWidgetKind, provider: NextEpisodeProvider()) { entry in
            NextEpisodeView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(entry.item.map { Identifiers.animeURL(malID: $0.malID) })
        }
        .configurationDisplayName("Próximo episodio")
        .description("El siguiente episodio de lo que estás viendo.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

struct NextEpisodeView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextEpisodeEntry

    var body: some View {
        if let item = entry.item {
            content(item)
        } else {
            empty
        }
    }

    @ViewBuilder
    private func content(_ item: ComplicationSnapshot.Item) -> some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Gauge(value: Double(item.episodesWatched), in: 0 ... Double(max(item.episodesTotal ?? max(item.episodesWatched, 1), 1))) {
                    EmptyView()
                } currentValueLabel: {
                    VStack(spacing: 0) {
                        Text("\(item.nextEpisode ?? item.episodesWatched + 1)").font(.headline.weight(.bold)).monospacedDigit()
                        Text("ep").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(Theme.accent)
            }
        case .accessoryInline:
            if let airs = item.nextAiringAt {
                Text("\(shortTitle(item.title)) · ep \(item.nextEpisode ?? 0) · \(airs, style: .relative)")
            } else {
                Text("\(shortTitle(item.title)) · ep \(item.nextEpisode ?? 0)")
            }
        case .accessoryCorner:
            Text("Ep \(item.nextEpisode ?? 0)")
                .font(.headline.weight(.bold))
                .widgetLabel {
                    if let airs = item.nextAiringAt {
                        Text(airs, style: .relative)
                    } else {
                        Text(shortTitle(item.title))
                    }
                }
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text("PRÓXIMO EPISODIO").font(.caption2.weight(.bold)).foregroundStyle(Theme.accent).widgetAccentable()
                Text(item.title).font(.subheadline.weight(.bold)).lineLimit(1)
                if let airs = item.nextAiringAt {
                    Text("Ep \(item.nextEpisode ?? 0) · \(airs, style: .relative)").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Ep \(item.nextEpisode ?? 0) · horario desconocido").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var empty: some View {
        switch family {
        case .accessoryInline: Text("RecAnime · sin próximos")
        case .accessoryCorner: Text("—").widgetLabel { Text("Sin próximos") }
        case .accessoryCircular: ZStack { AccessoryWidgetBackground(); Image(systemName: "bookmark") }
        default: VStack(alignment: .leading) {
                Text("RECANIME").font(.caption2.weight(.bold)).foregroundStyle(Theme.accent); Text("Sin próximos episodios").font(.caption)
            }
        }
    }

    private func shortTitle(_ title: String) -> String {
        title.count > 18 ? String(title.prefix(17)) + "…" : title
    }
}
