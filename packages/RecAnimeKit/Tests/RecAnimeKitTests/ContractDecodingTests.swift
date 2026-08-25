import Foundation
@testable import RecAnimeCore
@testable import RecAnimeKitTesting
import Testing

/// Decodes the golden responses exported by the Go API: any drift between the Swift models and
/// the server contract fails here first.
@Suite("API contract decoding")
struct ContractDecodingTests {
    let decoder = JSONDecoder.recanime

    @Test func me() throws {
        let env = try decoder.decode(Envelope<User>.self, from: Fixtures.data("me"))
        #expect(env.data.email == "dev@example.com")
        #expect(env.data.settings.sfw == true)
    }

    @Test func animeDetail() throws {
        let env = try decoder.decode(Envelope<AnimeDetail>.self, from: Fixtures.data("anime_detail"))
        let d = env.data
        #expect(d.malId == 52991)
        #expect(d.airingStatus == .finished)
        #expect(d.episodes == 28)
        #expect(d.library?.status == .watching)
        #expect(d.library?.episodesWatched == 7)
        #expect(d.franchise?.entries.isEmpty == false)
        #expect(d.airedFrom != nil)
        #expect(env.meta?.cache == .miss || env.meta?.cache == .hit)
    }

    @Test func franchise() throws {
        let env = try decoder.decode(Envelope<Franchise>.self, from: Fixtures.data("anime_franchise"))
        #expect(env.data.entries.count >= 2)
        #expect(env.data.entries[0].resolved)
        #expect(FranchiseNavigator.next(after: 52991, in: env.data)?.malId == 59978)
    }

    @Test func lists() throws {
        let top = try decoder.decode(Envelope<[AnimeSummary]>.self, from: Fixtures.data("top"))
        #expect(top.data.count == 2)
        #expect(top.pagination?.perPage == 25)
        let season = try decoder.decode(Envelope<[AnimeSummary]>.self, from: Fixtures.data("season_now"))
        #expect(season.data.first?.imageURL != nil)
        let search = try decoder.decode(Envelope<[AnimeSummary]>.self, from: Fixtures.data("search"))
        #expect(search.data.isEmpty == false)
        let episodes = try decoder.decode(Envelope<[Episode]>.self, from: Fixtures.data("anime_episodes"))
        #expect(episodes.data.count == 28)
        let seasons = try decoder.decode(Envelope<[SeasonIndex]>.self, from: Fixtures.data("seasons_index"))
        #expect(seasons.data.first?.year != 0)
    }

    @Test func recommendations() throws {
        let env = try decoder.decode(Envelope<[Recommendation]>.self, from: Fixtures.data("recommendations"))
        #expect(env.data.first?.entries.count == 2)
        #expect(env.meta?.cache == .live)
    }

    @Test func library() throws {
        let grouped = try decoder.decode(Envelope<LibraryGroups>.self, from: Fixtures.data("library_grouped"))
        #expect(grouped.data.watching.count == 1)
        #expect(grouped.data.pending.count == 1)
        #expect(grouped.data.favorites.count == 1)
        let item = try decoder.decode(Envelope<LibraryItem>.self, from: Fixtures.data("library_item"))
        #expect(item.data.entry.status == .watching)
        #expect(item.data.progress.remaining == 21)
    }

    @Test func schedule() throws {
        let env = try decoder.decode(Envelope<[ScheduleItem]>.self, from: Fixtures.data("schedule"))
        #expect(env.meta?.stale == false)
        _ = env.data
    }

    @Test func errors() throws {
        let notFound = try decoder.decode(APIErrorBody.self, from: Fixtures.data("error_not_found"))
        #expect(notFound.error.code == "not_found")
        let validation = try decoder.decode(APIErrorBody.self, from: Fixtures.data("error_validation"))
        #expect(validation.error.code == "validation_error")
    }

    @Test func lenientEnums() throws {
        let json = #"{"status":"binge","favorite":false,"episodesWatched":1,"updatedAt":"2026-08-24T10:00:00Z"}"#
        let overlay = try decoder.decode(LibraryOverlay.self, from: Data(json.utf8))
        #expect(overlay.status == .unknown)
        #expect(ISO8601Parsers.parse("2026-08-25T03:22:16.041273Z") != nil)
        #expect(ISO8601Parsers.parse("2023-09-29T00:00:00Z") != nil)
    }
}
