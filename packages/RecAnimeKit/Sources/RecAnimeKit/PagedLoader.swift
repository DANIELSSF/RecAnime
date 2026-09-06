import Foundation
import Observation
import RecAnimeCore

/// Infinite-scroll loader over a paginated endpoint.
///
/// A single fetch is in flight at any time: starting a new first page cancels the previous one and
/// bumps `generation`, so a slow response that lands afterwards is dropped instead of leaking into
/// the new list. A failed page is never retried automatically; the UI calls `retryMore()`.
@MainActor
@Observable
public final class PagedLoader<Item: Identifiable & Sendable> where Item.ID: Sendable {
    public enum State: Equatable, Sendable {
        case idle, loading, loadingMore, exhausted, failed(APIError)
    }

    public typealias Fetch = @Sendable (_ page: Int) async throws -> APIResponse<[Item]>

    public private(set) var items: [Item] = []
    public private(set) var state: State = .idle
    public private(set) var meta: Meta?
    /// When the first page last landed. `nil` while the list only holds seeded (snapshot) items.
    public private(set) var lastLoadedAt: Date?

    private var nextPage = 1
    private var seen: Set<Item.ID> = []
    private var fetch: Fetch
    /// The one in-flight fetch, cancelled whenever a newer load starts.
    private var inFlight: Task<APIResponse<[Item]>, Error>?
    /// Bumped by every load; a result carrying an older token is ignored.
    private var generation = 0

    public init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    /// Replaces the fetch function (filter change) and reloads. The old rows go away at once: another
    /// filter's results must not linger under the new one, even if the new fetch then fails.
    public func replace(fetch: @escaping Fetch) async {
        self.fetch = fetch
        items = []
        seen = []
        nextPage = 1
        await loadFirst()
    }

    /// Reloads the first page. Whatever is on screen (a previous load or a snapshot) stays until the
    /// new page lands, so an offline refresh degrades to "stale rows + retry" instead of a blank list.
    public func loadFirst() async {
        inFlight?.cancel()
        inFlight = nil
        nextPage = 1
        state = .loading
        await load(page: 1, replacing: true)
    }

    /// Call from `onAppear` of rows: loads the next page when `item` is within the last 5.
    /// A `.failed` state stops here: recovering is an explicit `retryMore()`, never a row appearance.
    public func loadMoreIfNeeded(currentItem item: Item) async {
        switch state {
        case .loading, .loadingMore, .exhausted, .failed: return
        case .idle: break
        }
        guard let index = items.firstIndex(where: { $0.id == item.id }), index >= items.count - 5 else { return }
        state = .loadingMore
        await load(page: nextPage, replacing: false)
    }

    /// Retries the page that failed. When it was the first page (nothing loaded, or only seeded rows
    /// on screen) this reloads from scratch instead of appending page 1 after the snapshot.
    public func retryMore() async {
        guard case .failed = state else { return }
        guard !items.isEmpty, nextPage > 1 else {
            await loadFirst()
            return
        }
        state = .loadingMore
        await load(page: nextPage, replacing: false)
    }

    /// Hydrates an untouched loader from an offline snapshot. Paging still starts at page 1, so the
    /// first real `loadFirst()` replaces everything seeded here.
    public func seed(_ items: [Item]) {
        guard state == .idle, self.items.isEmpty, !items.isEmpty else { return }
        var fresh: [Item] = []
        var ids: Set<Item.ID> = []
        for item in items where !ids.contains(item.id) {
            ids.insert(item.id)
            fresh.append(item)
        }
        self.items = fresh
        seen = ids
        nextPage = 1
    }

    /// `replacing` makes a successful response the whole list (first page); otherwise it appends.
    private func load(page: Int, replacing: Bool) async {
        generation &+= 1
        let token = generation
        let task = Task { [fetch] in
            try await fetch(page)
        }
        inFlight = task
        do {
            let response = try await task.value
            guard token == generation else { return } // superseded: the newer load owns the state
            var fresh = replacing ? [] : items
            var ids = replacing ? Set<Item.ID>() : seen
            for item in response.data where !ids.contains(item.id) {
                ids.insert(item.id)
                fresh.append(item)
            }
            items = fresh
            seen = ids
            meta = response.meta
            // The server reports the page it actually served; it can skip forward past filtered pages.
            nextPage = (response.pagination?.page ?? page) + 1
            state = (response.pagination?.hasNextPage ?? false) ? .idle : .exhausted
            if page == 1 {
                lastLoadedAt = .now
            }
            inFlight = nil
        } catch is CancellationError {
            // A newer load superseded this one; leave its state alone.
            if token == generation {
                inFlight = nil
            }
        } catch let error as APIError where error == .cancelled {
            // Same, mapped by the API client.
            if token == generation {
                inFlight = nil
            }
        } catch {
            guard token == generation else { return }
            state = .failed((error as? APIError) ?? .network(code: -1))
            inFlight = nil
        }
    }

    public var isEmpty: Bool {
        items.isEmpty && (state == .exhausted || state == .idle)
    }
}
