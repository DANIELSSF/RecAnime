import Foundation
import RecAnimeCore

/// Typed access to every API route. Views and stores depend on this protocol so tests can mock it.
public protocol RecAnimeAPI: Sendable {
    func me() async throws -> User
    func updateSettings(_ patch: SettingsPatch) async throws -> Settings

    func anime(_ id: Int) async throws -> APIResponse<AnimeDetail>
    func franchise(_ id: Int, budget: Int?) async throws -> Franchise
    func episodes(_ id: Int, page: Int) async throws -> APIResponse<[Episode]>
    func animeRecommendations(_ id: Int) async throws -> [AnimeRecommendation]

    func seasonsIndex() async throws -> [SeasonIndex]
    func seasonNow(filter: String?, page: Int) async throws -> APIResponse<[AnimeSummary]>
    func seasonUpcoming(filter: String?, page: Int) async throws -> APIResponse<[AnimeSummary]>
    func season(year: Int, season: String, filter: String?, page: Int) async throws -> APIResponse<[AnimeSummary]>
    func top(filter: String?, type: String?, page: Int) async throws -> APIResponse<[AnimeSummary]>
    func recommendations(page: Int) async throws -> APIResponse<[Recommendation]>
    func search(_ q: String, page: Int) async throws -> APIResponse<[AnimeSummary]>
    func browse(_ query: BrowseQuery, page: Int) async throws -> APIResponse<[AnimeSummary]>
    func schedules(day: String, page: Int) async throws -> APIResponse<[AnimeSummary]>

    func library() async throws -> LibraryGroups
    func library(status: WatchStatus?, favorite: Bool?) async throws -> [LibraryItem]
    func libraryItem(_ id: Int) async throws -> LibraryItem
    func upsertLibrary(_ id: Int, _ patch: LibraryPatch) async throws -> LibraryItem
    func adjustEpisodes(_ id: Int, _ adjustment: EpisodesAdjustment) async throws -> LibraryItem
    func deleteLibrary(_ id: Int) async throws
    func batchLibrary(_ items: [LibraryBatchItem]) async throws -> [LibraryItem]
    func schedule(includeEpisodes: Bool) async throws -> APIResponse<[ScheduleItem]>
}

/// Production implementation backed by `APIClient`.
public struct LiveRecAnimeAPI: RecAnimeAPI {
    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func me() async throws -> User {
        try await client.send(.me).data
    }

    public func updateSettings(_ patch: SettingsPatch) async throws -> Settings {
        try await client.send(.updateSettings(patch)).data
    }

    public func anime(_ id: Int) async throws -> APIResponse<AnimeDetail> {
        try await client.send(.anime(id))
    }

    public func franchise(_ id: Int, budget: Int?) async throws -> Franchise {
        try await client.send(.franchise(id, budget: budget)).data
    }

    public func episodes(_ id: Int, page: Int) async throws -> APIResponse<[Episode]> {
        try await client.send(.episodes(id, page: page))
    }

    public func animeRecommendations(_ id: Int) async throws -> [AnimeRecommendation] {
        try await client.send(.animeRecommendations(id)).data
    }

    public func seasonsIndex() async throws -> [SeasonIndex] {
        try await client.send(.seasonsIndex).data
    }

    public func seasonNow(filter: String?, page: Int) async throws -> APIResponse<[AnimeSummary]> {
        try await client.send(.seasonNow(
            filter: filter,
            page: page
        ))
    }

    public func seasonUpcoming(filter: String?, page: Int) async throws -> APIResponse<[AnimeSummary]> {
        try await client.send(.seasonUpcoming(
            filter: filter,
            page: page
        ))
    }

    public func season(year: Int, season: String, filter: String?, page: Int) async throws -> APIResponse<[AnimeSummary]> {
        try await client.send(.season(year: year, season: season, filter: filter, page: page))
    }

    public func top(filter: String?, type: String?, page: Int) async throws -> APIResponse<[AnimeSummary]> {
        try await client.send(.top(
            filter: filter,
            type: type,
            page: page
        ))
    }

    public func recommendations(page: Int) async throws -> APIResponse<[Recommendation]> {
        try await client.send(.recommendations(page: page))
    }

    public func search(_ q: String, page: Int) async throws -> APIResponse<[AnimeSummary]> {
        try await client.send(.search(q, page: page))
    }

    public func browse(_ query: BrowseQuery, page: Int) async throws -> APIResponse<[AnimeSummary]> {
        try await client.send(.browse(query, page: page))
    }

    public func schedules(
        day: String,
        page: Int
    ) async throws -> APIResponse<[AnimeSummary]> {
        try await client.send(.schedules(day: day, page: page))
    }

    public func library() async throws -> LibraryGroups {
        try await client.send(.library).data
    }

    public func library(status: WatchStatus?, favorite: Bool?) async throws -> [LibraryItem] {
        try await client.send(.library(
            status: status,
            favorite: favorite
        )).data
    }

    public func libraryItem(_ id: Int) async throws -> LibraryItem {
        try await client.send(.libraryItem(id)).data
    }

    public func upsertLibrary(_ id: Int, _ patch: LibraryPatch) async throws -> LibraryItem {
        try await client.send(.upsertLibrary(id, patch)).data
    }

    public func adjustEpisodes(_ id: Int, _ adjustment: EpisodesAdjustment) async throws -> LibraryItem {
        try await client.send(.adjustEpisodes(
            id,
            adjustment
        )).data
    }

    public func deleteLibrary(_ id: Int) async throws {
        try await client.sendNoContent(.deleteLibrary(id))
    }

    public func batchLibrary(_ items: [LibraryBatchItem]) async throws -> [LibraryItem] {
        try await client.send(.batchLibrary(items)).data
    }

    public func schedule(includeEpisodes: Bool) async throws -> APIResponse<[ScheduleItem]> {
        try await client
            .send(.schedule(includeEpisodes: includeEpisodes))
    }
}
