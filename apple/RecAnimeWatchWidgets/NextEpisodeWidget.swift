import RecAnimeCore
import RecAnimeUI
import SwiftUI
import WidgetKit

/// "Próximo episodio" complication. The timeline reads the App Group snapshot written by the
/// Watch app (added in the Watch milestone); today it renders a placeholder entry.
struct NextEpisodeEntry: TimelineEntry {
    let date: Date
    let title: String
    let episode: Int
    let airsAt: Date
    let malID: Int
}

struct NextEpisodeProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextEpisodeEntry {
        NextEpisodeEntry(date: .now, title: "Frieren 2nd Season", episode: 8, airsAt: .now.addingTimeInterval(2 * 3600), malID: 59978)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (NextEpisodeEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<NextEpisodeEntry>) -> Void) {
        completion(Timeline(entries: [placeholder(in: context)], policy: .after(.now.addingTimeInterval(3600))))
    }
}

struct NextEpisodeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Identifiers.nextEpisodeWidgetKind, provider: NextEpisodeProvider()) { entry in
            NextEpisodeView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(Identifiers.animeURL(malID: entry.malID))
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
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(entry.episode)").font(.headline.weight(.bold)).monospacedDigit()
                    Text("ep").font(.caption2).foregroundStyle(.secondary)
                }
            }
        case .accessoryInline:
            Text("\(entry.title) · ep \(entry.episode) · \(entry.airsAt, style: .relative)")
        case .accessoryCorner:
            Text("Ep \(entry.episode)")
                .font(.headline.weight(.bold))
                .widgetLabel { Text(entry.airsAt, style: .relative) }
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text("PRÓXIMO EPISODIO").font(.caption2.weight(.bold)).foregroundStyle(Theme.accent).widgetAccentable()
                Text(entry.title).font(.subheadline.weight(.bold)).lineLimit(1)
                Text("Ep \(entry.episode) · \(entry.airsAt, style: .relative)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
