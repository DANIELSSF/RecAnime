import Foundation
import RecAnimeCore
import RecAnimeKit
import WidgetKit

/// Writes the complication data to the App Group and asks WidgetKit to reload.
enum ComplicationSnapshotWriter {
    /// The schedule is only as fresh as the last server fetch, so a +1 made on the Watch would leave the
    /// complication an episode behind. The library (already updated locally) wins over it.
    static func write(schedule: [ScheduleItem], library: LibraryStore, store: AppGroupStore) {
        let snapshot = ComplicationSnapshot.from(schedule: schedule, now: .now)
        let items = snapshot.items.map { item -> ComplicationSnapshot.Item in
            guard let watched = library.items[item.malID]?.entry.episodesWatched, watched > item.episodesWatched else { return item }
            var fresh = item
            fresh.episodesWatched = watched
            if (fresh.nextEpisode ?? 0) <= watched {
                fresh.nextEpisode = watched + 1
            }
            return fresh
        }
        try? store.write(ComplicationSnapshot(generatedAt: snapshot.generatedAt, items: items), file: AppGroupStore.complicationFile)
        WidgetCenter.shared.reloadTimelines(ofKind: Identifiers.nextEpisodeWidgetKind)
    }
}
