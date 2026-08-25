import Foundation
import Observation
import RecAnimeCore

/// Last summaries the user saw in lists, so the detail page can paint its hero and title
/// instantly (during the zoom transition) while the full record loads.
@MainActor
@Observable
final class SummaryCache {
    private var summaries: [Int: AnimeSummary] = [:]

    func remember(_ summary: AnimeSummary) {
        summaries[summary.malId] = summary
    }

    func remember(_ entry: RecommendationEntry) {
        guard summaries[entry.malId] == nil else { return }
        summaries[entry.malId] = AnimeSummary(
            malId: entry.malId,
            title: entry.title,
            imageUrl: entry.imageUrl,
            imageLargeUrl: entry.imageUrl,
            library: entry.library
        )
    }

    subscript(malID: Int) -> AnimeSummary? {
        summaries[malID]
    }
}
