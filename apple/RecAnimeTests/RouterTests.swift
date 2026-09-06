import Foundation
@testable import RecAnime
import Testing

/// Deep-link handling and in-tab navigation: locks the guard on malformed ids, the "replace the
/// destination path" rule for links/notifications, and the "skip when already on top" rule for
/// in-app pushes.
@MainActor
@Suite("Router")
struct RouterTests {
    @Test("an anime deep link opens the library tab with a fresh path")
    func animeDeepLink() throws {
        let router = Router()
        let url = try #require(URL(string: "recanime://anime/52991"))
        #expect(router.handle(url))
        #expect(router.tab == .library)
        #expect(router.libraryPath == [.anime(52991, source: nil)])
    }

    @Test("handling the same anime link twice does not stack a duplicate")
    func animeDeepLinkIsIdempotent() throws {
        let router = Router()
        let url = try #require(URL(string: "recanime://anime/52991"))
        #expect(router.handle(url))
        #expect(router.handle(url))
        #expect(router.libraryPath == [.anime(52991, source: nil)])
    }

    @Test(
        "malformed anime ids are rejected without touching state",
        arguments: ["recanime://anime/0", "recanime://anime/-3", "recanime://anime/abc"]
    )
    func malformedAnimeId(_ raw: String) throws {
        let router = Router()
        router.tab = .search
        router.libraryPath = [.seasonBrowser]
        let url = try #require(URL(string: raw))

        #expect(router.handle(url) == false)
        #expect(router.tab == .search)
        #expect(router.libraryPath == [.seasonBrowser])
    }

    @Test("the library link resets the tab and clears its path")
    func libraryLink() throws {
        let router = Router()
        router.tab = .search
        router.libraryPath = [.seasonBrowser]
        let url = try #require(URL(string: "recanime://library"))

        #expect(router.handle(url))
        #expect(router.tab == .library)
        #expect(router.libraryPath.isEmpty)
    }

    @Test("the explore link opens the season tab at the browser route")
    func exploreLink() throws {
        let router = Router()
        let url = try #require(URL(string: "recanime://explore"))

        #expect(router.handle(url))
        #expect(router.tab == .season)
        #expect(router.seasonPath == [.seasonBrowser])
    }

    @Test("the top link resets the tab and clears its path")
    func topLink() throws {
        let router = Router()
        router.topPath = [.anime(1)]
        let url = try #require(URL(string: "recanime://top"))

        #expect(router.handle(url))
        #expect(router.tab == .top)
        #expect(router.topPath.isEmpty)
    }

    @Test("the discover link resets the tab and clears its path")
    func discoverLink() throws {
        let router = Router()
        router.recommendationsPath = [.anime(1)]
        let url = try #require(URL(string: "recanime://discover"))

        #expect(router.handle(url))
        #expect(router.tab == .recommendations)
        #expect(router.recommendationsPath.isEmpty)
    }

    @Test("a foreign scheme is rejected")
    func foreignScheme() throws {
        let router = Router()
        let url = try #require(URL(string: "https://example.com/anime/1"))

        #expect(router.handle(url) == false)
        #expect(router.tab == .season)
    }

    @Test("an unknown host under our own scheme is rejected")
    func unknownHost() throws {
        let router = Router()
        let url = try #require(URL(string: "recanime://unknown"))

        #expect(router.handle(url) == false)
        #expect(router.tab == .season)
    }

    @Test("open(anime:in:) replaces the destination tab's path")
    func openReplacesDestinationPath() {
        let router = Router()
        router.libraryPath = [.seasonBrowser, .anime(10)]

        router.open(anime: 20, in: .library)

        #expect(router.tab == .library)
        #expect(router.libraryPath == [.anime(20, source: nil)])
    }

    @Test("open(anime:) appends to the current tab's path")
    func openAppendsToCurrentTab() {
        let router = Router()
        router.tab = .season
        router.seasonPath = [.seasonBrowser]

        router.open(anime: 30)

        #expect(router.seasonPath == [.seasonBrowser, .anime(30, source: nil)])
    }

    @Test("open(anime:) skips the push when the top route is already that anime")
    func openSkipsDuplicateTop() {
        let router = Router()
        router.tab = .season
        router.seasonPath = [.anime(30)]

        router.open(anime: 30, source: "grid") // a different source still counts as the same page

        #expect(router.seasonPath == [.anime(30, source: nil)])
    }

    @Test("Route.calendar exists and can be pushed")
    func calendarRoute() {
        let router = Router()
        router.seasonPath.append(.calendar)
        #expect(router.seasonPath == [.calendar])
    }

    @Test("SeasonKind.title strings are unchanged")
    func seasonKindTitles() {
        #expect(SeasonKind.now.title == "Esta temporada")
        #expect(SeasonKind.upcoming.title == "Próximamente")
        #expect(SeasonKind.specific(year: 2026, season: "winter").title == "Invierno 2026")
        #expect(SeasonKind.specific(year: 2026, season: "spring").title == "Primavera 2026")
        #expect(SeasonKind.specific(year: 2026, season: "summer").title == "Verano 2026")
        #expect(SeasonKind.specific(year: 2026, season: "fall").title == "Otoño 2026")
    }
}
