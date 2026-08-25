import Foundation
import RecAnimeCore
import WidgetKit

/// Writes the complication data to the App Group and asks WidgetKit to reload.
enum ComplicationSnapshotWriter {
    static func write(schedule: [ScheduleItem], store: AppGroupStore) {
        let snapshot = ComplicationSnapshot.from(schedule: schedule, now: .now)
        try? store.write(snapshot, file: AppGroupStore.complicationFile)
        WidgetCenter.shared.reloadTimelines(ofKind: Identifiers.nextEpisodeWidgetKind)
    }
}
