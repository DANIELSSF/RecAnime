import Foundation
@testable import RecAnimeCore
@testable import RecAnimeKit
@testable import RecAnimeKitTesting
import Testing

/// In-memory API used by the store tests.
final class FakeAPI: RecAnimeAPI, @unchecked Sendable {
    private let lock = NSLock()
    var items: [Int: LibraryItem] = [:]
    var failNext = false
    var adjustCalls: [(Int, EpisodesAdjustment)] = []

    private func item(_ id: Int, _ patch: LibraryPatch?, _ episodes: Int?) throws -> LibraryItem {
        lock.lock(); defer { lock.unlock() }
        if failNext {
            failNext = false; throw APIError.server(status: 502, code: "upstream_unavailable", message: nil)
        }
        var it = items[id] ?? Self.sample(id)
        if let patch {
            if let s = patch.status {
                it.entry.status = s
            }
            if let f = patch.favorite {
                it.entry.favorite = f
            }
            if let e = patch.episodesWatched {
                it.entry.episodesWatched = e
            }
            // Server rule: marking a season as watched completes its progress.
            if patch.status == .watched, patch.episodesWatched == nil, let total = it.progress.episodesTotal {
                it.entry.episodesWatched = total
            }
        }
        if let episodes {
            it.entry.episodesWatched = min(episodes, it.progress.episodesTotal ?? episodes)
        }
        it.entry.updatedAt = .now
        it.progress.remaining = it.progress.episodesTotal.map { max($0 - it.entry.episodesWatched, 0) }
        items[id] = it
        return it
    }

    static func sample(_ id: Int) -> LibraryItem {
        let summary = AnimeSummary(
            malId: id,
            title: "Anime \(id)",
            titleEnglish: nil,
            imageUrl: "",
            imageLargeUrl: "",
            type: "TV",
            episodes: 12,
            status: "Currently Airing",
            airingStatus: .airing,
            airing: true,
            score: 8,
            rank: 1,
            popularity: 1,
            members: 1,
            year: 2026,
            season: "summer",
            rating: nil,
            isAdult: false,
            library: nil
        )
        return LibraryItem(
            anime: summary,
            entry: LibraryEntry(status: .pending, favorite: false, episodesWatched: 0, createdAt: .now, updatedAt: .now),
            progress: Progress(episodesTotal: 12, remaining: 12)
        )
    }

    func me() async throws -> User {
        fatalError()
    }

    func updateSettings(_ patch: SettingsPatch) async throws -> Settings {
        fatalError()
    }

    func anime(_ id: Int) async throws -> APIResponse<AnimeDetail> {
        fatalError()
    }

    func franchise(_ id: Int, budget: Int?) async throws -> Franchise {
        fatalError()
    }

    func episodes(_ id: Int, page: Int) async throws -> APIResponse<[Episode]> {
        fatalError()
    }

    func animeRecommendations(_ id: Int) async throws -> [AnimeRecommendation] {
        fatalError()
    }

    func seasonsIndex() async throws -> [SeasonIndex] {
        fatalError()
    }

    func seasonNow(filter: String?, page: Int) async throws -> APIResponse<[AnimeSummary]> {
        fatalError()
    }

    func seasonUpcoming(filter: String?, page: Int) async throws -> APIResponse<[AnimeSummary]> {
        fatalError()
    }

    func season(year: Int, season: String, filter: String?, page: Int) async throws -> APIResponse<[AnimeSummary]> {
        fatalError()
    }

    func top(filter: String?, type: String?, page: Int) async throws -> APIResponse<[AnimeSummary]> {
        fatalError()
    }

    func recommendations(page: Int) async throws -> APIResponse<[Recommendation]> {
        fatalError()
    }

    func search(_ q: String, page: Int) async throws -> APIResponse<[AnimeSummary]> {
        fatalError()
    }

    func browse(_ query: BrowseQuery, page: Int) async throws -> APIResponse<[AnimeSummary]> {
        fatalError()
    }

    func schedules(day: String, page: Int) async throws -> APIResponse<[AnimeSummary]> {
        fatalError()
    }

    func schedule(includeEpisodes: Bool) async throws -> APIResponse<[ScheduleItem]> {
        APIResponse(data: [])
    }

    func library() async throws -> LibraryGroups {
        let all = lock.withLock { Array(items.values) }
        return LibraryGroups(
            watching: all.filter { $0.entry.status == .watching },
            pending: all.filter { $0.entry.status == .pending },
            watched: all.filter { $0.entry.status == .watched },
            favorites: all.filter(\.entry.favorite)
        )
    }

    func library(status: WatchStatus?, favorite: Bool?) async throws -> [LibraryItem] {
        try await library().all
    }

    func libraryItem(_ id: Int) async throws -> LibraryItem {
        try item(id, nil, nil)
    }

    func upsertLibrary(_ id: Int, _ patch: LibraryPatch) async throws -> LibraryItem {
        try item(id, patch, nil)
    }

    func adjustEpisodes(_ id: Int, _ adjustment: EpisodesAdjustment) async throws -> LibraryItem {
        lock.withLock { adjustCalls.append((id, adjustment)) }
        return try item(id, nil, adjustment.episodesWatched)
    }

    func batchLibrary(_ items: [LibraryBatchItem]) async throws -> [LibraryItem] {
        var out: [LibraryItem] = []
        for it in items {
            try out.append(item(it.malId, LibraryPatch(status: it.status, favorite: it.favorite, episodesWatched: it.episodesWatched), nil))
        }
        return out
    }

    func deleteLibrary(_ id: Int) async throws {
        try lock.withLock {
            if failNext {
                failNext = false; throw APIError.server(status: 500, code: "internal", message: nil)
            }
            items[id] = nil
        }
    }
}

@Suite("LibraryStore")
@MainActor
struct LibraryStoreTests {
    @Test("optimistic status change is confirmed by the server")
    func optimisticStatus() async throws {
        let api = FakeAPI()
        let store = LibraryStore(api: api, debounce: .zero)
        let anime = FakeAPI.sample(1).anime
        let item = try await store.setStatus(.watching, for: anime)
        #expect(item.entry.status == .watching)
        #expect(store.groups.watching.count == 1)
        #expect(store.overlay(for: 1)?.status == .watching)
        #expect(store.version > 0)
    }

    @Test("failed mutation rolls back")
    func rollback() async {
        let api = FakeAPI()
        let store = LibraryStore(api: api, debounce: .zero)
        let anime = FakeAPI.sample(2).anime
        api.failNext = true
        await #expect(throws: APIError.self) {
            _ = try await store.toggleFavorite(for: anime)
        }
        #expect(store.items[2] == nil)
        #expect(store.lastError?.isRetryable == true)
    }

    @Test("increments are coalesced into one absolute request and clamped")
    func coalescedIncrements() async {
        let api = FakeAPI()
        let store = LibraryStore(api: api, debounce: .milliseconds(50))
        let anime = FakeAPI.sample(3).anime
        store.increment(for: anime)
        store.increment(for: anime)
        store.increment(for: anime)
        #expect(store.items[3]?.entry.episodesWatched == 3)
        #expect(store.items[3]?.entry.status == .watching)
        await store.flush()
        #expect(api.adjustCalls.count == 1)
        #expect(api.adjustCalls.first?.1.episodesWatched == 3)
        for _ in 0 ..< 20 {
            store.increment(for: anime)
        }
        #expect(store.items[3]?.entry.episodesWatched == 12)
        await store.flush()
        #expect(store.items[3]?.progress.remaining == 0)
    }

    @Test("watched fills the episode count; nowWatching picks an unfinished entry")
    func watchedAndNowWatching() async throws {
        let api = FakeAPI()
        let store = LibraryStore(api: api, debounce: .zero)
        _ = try await store.setStatus(.watching, for: FakeAPI.sample(4).anime)
        let done = try await store.setStatus(.watched, for: FakeAPI.sample(5).anime)
        #expect(done.entry.episodesWatched == 12)
        #expect(store.nowWatching?.anime.malId == 4)
        try await store.remove(4)
        #expect(store.nowWatching == nil)
    }
}

@Suite("LibraryStore · franchise")
@MainActor
struct LibraryStoreFranchiseTests {
    @Test("mark watched through season 2 and start season 3")
    func markThrough() async throws {
        let api = FakeAPI()
        let store = LibraryStore(api: api, debounce: .zero)
        let entries = (1 ... 4).map { i in
            FranchiseEntry(
                malId: 100 + i,
                title: "S\(i)",
                position: i,
                resolved: i != 4,
                relationToPrevious: i == 1 ? nil : "Sequel",
                anime: i == 4 ? nil : FakeAPI.sample(100 + i).anime
            )
        }
        let franchise = Franchise(entries: entries, requestedIndex: 0, currentIndex: 0, nextSeason: entries[1], complete: false)
        let result = try await store.markWatched(through: 1, in: franchise, startNext: true)
        #expect(result.count == 3)
        #expect(store.items[101]?.entry.status == .watched)
        #expect(store.items[101]?.entry.episodesWatched == 12)
        #expect(store.items[102]?.entry.status == .watched)
        #expect(store.items[103]?.entry.status == .watching)
        #expect(store.items[104] == nil)
        #expect(store.nowWatching?.anime.malId == 103)
    }

    @Test("a failed batch rolls everything back")
    func rollback() async {
        let api = FakeAPI()
        let store = LibraryStore(api: api, debounce: .zero)
        let entries = (1 ... 2).map { i in FranchiseEntry(
            malId: 200 + i,
            title: "S\(i)",
            position: i,
            resolved: true,
            anime: FakeAPI.sample(200 + i).anime
        ) }
        let franchise = Franchise(entries: entries, requestedIndex: 0, currentIndex: 0, complete: true)
        api.failNext = true
        await #expect(throws: APIError.self) { _ = try await store.markWatched(through: 1, in: franchise, startNext: false) }
        #expect(store.items.isEmpty)
    }
}

@Suite("PagedLoader")
@MainActor
struct PagedLoaderTests {
    @Test("appends pages, de-duplicates and stops at the last page")
    func paging() async {
        let loader = PagedLoader<AnimeSummary> { page in
            let items = (0 ..< 3).map { FakeAPI.sample(page * 10 + $0).anime } + [FakeAPI.sample(10).anime] // 10 repeats on page 1
            return APIResponse(data: items, pagination: Pagination(page: page, perPage: 25, hasNextPage: page < 2, lastVisiblePage: 2, total: 6))
        }
        await loader.loadFirst()
        #expect(loader.items.count == 3)
        #expect(loader.state == .idle)
        await loader.loadMoreIfNeeded(currentItem: loader.items[2])
        #expect(loader.items.count == 6)
        #expect(loader.state == .exhausted)
        await loader.loadMoreIfNeeded(currentItem: loader.items[5])
        #expect(loader.items.count == 6)
    }

    @Test("failures surface as state")
    func failure() async {
        let loader = PagedLoader<AnimeSummary> { _ in throw APIError.server(status: 502, code: "upstream_unavailable", message: nil) }
        await loader.loadFirst()
        #expect(loader.state == .failed(.server(status: 502, code: "upstream_unavailable", message: nil)))
    }
}
