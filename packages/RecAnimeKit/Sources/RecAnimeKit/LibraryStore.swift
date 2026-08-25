import Foundation
import Observation
import RecAnimeCore

/// The user's lists with optimistic updates. Every mutation applies locally first, then talks to the
/// API; failures roll back and rethrow. Episode increments are coalesced into one absolute PUT.
@MainActor
@Observable
public final class LibraryStore {
    public private(set) var groups = LibraryGroups()
    public private(set) var items: [Int: LibraryItem] = [:]
    /// Bumped on every committed change so notification planning and Watch sync can react.
    public private(set) var version = 0
    public private(set) var isLoading = false
    public private(set) var lastError: APIError?

    private let api: any RecAnimeAPI
    private let debounce: Duration
    private var pendingEpisodes: [Int: Task<Void, Never>] = [:]

    public init(api: any RecAnimeAPI, debounce: Duration = .milliseconds(400)) {
        self.api = api
        self.debounce = debounce
    }

    // MARK: Reading

    public func overlay(for malID: Int) -> LibraryOverlay? {
        guard let item = items[malID] else { return nil }
        return LibraryOverlay(
            status: item.entry.status,
            favorite: item.entry.favorite,
            episodesWatched: item.entry.episodesWatched,
            updatedAt: item.entry.updatedAt
        )
    }

    /// The most recently touched "watching" entry that still has episodes left.
    public var nowWatching: LibraryItem? {
        groups.watching
            .filter { ($0.progress.remaining ?? .max) > 0 }
            .max { $0.entry.updatedAt < $1.entry.updatedAt }
    }

    // MARK: Loading

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let groups = try await api.library()
            apply(groups)
            lastError = nil
        } catch let error as APIError {
            lastError = error
        } catch {
            lastError = .network(code: -1)
        }
    }

    /// Replaces the local state with a snapshot pushed by the iPhone (Watch, before its first fetch).
    public func applySnapshot(_ snapshot: [LibraryItem]) {
        var merged = items
        for item in snapshot {
            merged[item.anime.malId] = item
        }
        items = merged
        rebuildGroups()
        version += 1
    }

    /// Seeds an item that arrived embedded in another response (e.g. the detail page).
    public func seed(_ summary: AnimeSummary) {
        guard let overlay = summary.library, items[summary.malId] == nil else { return }
        let entry = LibraryEntry(
            status: overlay.status,
            favorite: overlay.favorite,
            episodesWatched: overlay.episodesWatched,
            createdAt: overlay.updatedAt,
            updatedAt: overlay.updatedAt
        )
        let remaining = summary.episodes.map { max($0 - overlay.episodesWatched, 0) }
        upsertLocal(LibraryItem(anime: summary, entry: entry, progress: Progress(episodesTotal: summary.episodes, remaining: remaining)))
    }

    // MARK: Mutations

    public func setStatus(_ status: WatchStatus, for anime: AnimeSummary) async throws -> LibraryItem {
        // Sending the count explicitly keeps the client independent from the server-side rule.
        let completed = status == .watched ? anime.episodes : nil
        return try await mutate(anime) { entry in
            entry.status = status
            if let completed {
                entry.episodesWatched = completed
            }
        } remote: { [api] in
            try await api.upsertLibrary(anime.malId, LibraryPatch(status: status, episodesWatched: completed))
        }
    }

    public func toggleFavorite(for anime: AnimeSummary) async throws -> LibraryItem {
        let target = !(items[anime.malId]?.entry.favorite ?? anime.library?.favorite ?? false)
        return try await mutate(anime) { entry in
            entry.favorite = target
        } remote: { [api] in
            try await api.upsertLibrary(anime.malId, LibraryPatch(favorite: target))
        }
    }

    /// Absolute progress (clamped by the server); sends immediately.
    public func setEpisodes(_ count: Int, for anime: AnimeSummary) async throws -> LibraryItem {
        let clamped = clamp(count, total: anime.episodes)
        return try await mutate(anime) { entry in
            entry.episodesWatched = clamped
            if entry.status == .pending, clamped > 0 {
                entry.status = .watching
            }
        } remote: { [api] in
            try await api.adjustEpisodes(anime.malId, .set(clamped))
        }
    }

    /// Relative progress with coalescing: rapid taps become one absolute request after `debounce`.
    public func increment(for anime: AnimeSummary, by delta: Int = 1) {
        let current = items[anime.malId]?.entry.episodesWatched ?? anime.library?.episodesWatched ?? 0
        let target = clamp(current + delta, total: anime.episodes)
        applyLocal(anime) { entry in
            entry.episodesWatched = target
            if entry.status == .pending, target > 0 {
                entry.status = .watching
            }
        }
        pendingEpisodes[anime.malId]?.cancel()
        pendingEpisodes[anime.malId] = Task { [weak self, debounce, api] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            let final = items[anime.malId]?.entry.episodesWatched ?? target
            do {
                let item = try await api.adjustEpisodes(anime.malId, .set(final))
                upsertLocal(item)
                lastError = nil
            } catch let error as APIError {
                self.lastError = error
                await self.load()
            } catch {
                lastError = .network(code: -1)
            }
            pendingEpisodes[anime.malId] = nil
        }
    }

    /// Waits for coalesced increments (tests, app going to background).
    public func flush() async {
        for task in pendingEpisodes.values {
            await task.value
        }
    }

    public func remove(_ malID: Int) async throws {
        let snapshot = items
        if let removed = items.removeValue(forKey: malID) {
            _ = removed
            rebuildGroups()
            version += 1
        }
        do {
            try await api.deleteLibrary(malID)
        } catch {
            items = snapshot
            rebuildGroups()
            throw error
        }
    }

    // MARK: Internals

    private func mutate(
        _ anime: AnimeSummary,
        local: (inout LibraryEntry) -> Void,
        remote: @Sendable () async throws -> LibraryItem
    ) async throws -> LibraryItem {
        let snapshot = items
        applyLocal(anime, local)
        do {
            let item = try await remote()
            upsertLocal(item)
            lastError = nil
            return item
        } catch {
            items = snapshot
            rebuildGroups()
            if let apiError = error as? APIError {
                lastError = apiError
            }
            throw error
        }
    }

    private func applyLocal(_ anime: AnimeSummary, _ change: (inout LibraryEntry) -> Void) {
        var item = items[anime.malId] ?? LibraryItem(
            anime: anime,
            entry: LibraryEntry(status: .pending, favorite: false, episodesWatched: 0, createdAt: .now, updatedAt: .now),
            progress: Progress(episodesTotal: anime.episodes, remaining: anime.episodes)
        )
        change(&item.entry)
        item.entry.updatedAt = .now
        item.progress.remaining = item.progress.episodesTotal.map { max($0 - item.entry.episodesWatched, 0) }
        item.anime.library = LibraryOverlay(
            status: item.entry.status,
            favorite: item.entry.favorite,
            episodesWatched: item.entry.episodesWatched,
            updatedAt: item.entry.updatedAt
        )
        upsertLocal(item)
    }

    private func upsertLocal(_ item: LibraryItem) {
        items[item.anime.malId] = item
        rebuildGroups()
        version += 1
    }

    private func apply(_ groups: LibraryGroups) {
        items = Dictionary(uniqueKeysWithValues: groups.all.map { ($0.anime.malId, $0) })
        rebuildGroups()
        version += 1
    }

    private func rebuildGroups() {
        let sorted = items.values.sorted { $0.entry.updatedAt > $1.entry.updatedAt }
        groups = LibraryGroups(
            watching: sorted.filter { $0.entry.status == .watching },
            pending: sorted.filter { $0.entry.status == .pending },
            watched: sorted.filter { $0.entry.status == .watched },
            favorites: sorted.filter(\.entry.favorite)
        )
    }

    private func clamp(_ value: Int, total: Int?) -> Int {
        var v = max(value, 0)
        if let total, total > 0 {
            v = min(v, total)
        }
        return v
    }
}
