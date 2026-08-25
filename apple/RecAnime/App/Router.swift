import Foundation
import Observation
import RecAnimeCore
import SwiftUI

/// Navigation destinations shared by every tab.
enum Route: Hashable {
    /// `source` names the `zoomSource` the page was opened from (nil → standard push).
    case anime(Int, source: String? = nil)
    case seasonGrid(SeasonKind)
    case seasonBrowser
    case franchise(Int)
}

enum SeasonKind: Hashable {
    case now
    case upcoming
    case specific(year: Int, season: String)

    var title: String {
        switch self {
        case .now: "Esta temporada"
        case .upcoming: "Próximamente"
        case let .specific(year, season): "\(SeasonKind.localizedSeason(season)) \(year)"
        }
    }

    static func localizedSeason(_ season: String) -> String {
        switch season {
        case "winter": "Invierno"
        case "spring": "Primavera"
        case "summer": "Verano"
        case "fall": "Otoño"
        default: season.capitalized
        }
    }
}

enum AppTab: Hashable {
    case season, top, recommendations, library, search
}

/// Tab selection plus one navigation path per tab; also resolves deep links.
@MainActor
@Observable
final class Router {
    var tab: AppTab = .season
    var seasonPath: [Route] = []
    var topPath: [Route] = []
    var recommendationsPath: [Route] = []
    var libraryPath: [Route] = []
    var searchPath: [Route] = []

    func path(for tab: AppTab) -> Binding<[Route]> {
        switch tab {
        case .season: Binding(get: { self.seasonPath }, set: { self.seasonPath = $0 })
        case .top: Binding(get: { self.topPath }, set: { self.topPath = $0 })
        case .recommendations: Binding(get: { self.recommendationsPath }, set: { self.recommendationsPath = $0 })
        case .library: Binding(get: { self.libraryPath }, set: { self.libraryPath = $0 })
        case .search: Binding(get: { self.searchPath }, set: { self.searchPath = $0 })
        }
    }

    /// Pushes the anime page onto the current tab (or a specific one); `source` enables the zoom transition.
    func open(anime malID: Int, source: String? = nil, in destination: AppTab? = nil) {
        if let destination {
            tab = destination
        }
        path(for: tab).wrappedValue.append(.anime(malID, source: source))
    }

    /// Same as `open`, remembering the summary so the detail page renders instantly.
    func open(_ anime: AnimeSummary, source: String? = nil, remembering cache: SummaryCache) {
        cache.remember(anime)
        open(anime: anime.malId, source: source)
    }

    /// `recanime://anime/<id>` and `recanime://library?status=watching`.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == Identifiers.urlScheme else { return false }
        switch url.host {
        case "anime":
            guard let id = Int(url.lastPathComponent) else { return false }
            open(anime: id, in: .library)
            return true
        case "library":
            tab = .library
            libraryPath = []
            return true
        case "explore":
            tab = .season
            seasonPath = [.seasonBrowser]
            return true
        default:
            return false
        }
    }
}
