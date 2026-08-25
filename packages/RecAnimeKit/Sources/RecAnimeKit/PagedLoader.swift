import Foundation
import Observation
import RecAnimeCore

/// Infinite-scroll loader over a paginated endpoint.
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
    private var nextPage = 1
    private var seen: Set<Item.ID> = []
    private var fetch: Fetch
    private var current: Task<Void, Never>?

    public init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    /// Replaces the fetch function (filter change) and reloads.
    public func replace(fetch: @escaping Fetch) async {
        self.fetch = fetch
        await loadFirst()
    }

    public func loadFirst() async {
        current?.cancel()
        items = []
        seen = []
        nextPage = 1
        state = .loading
        await load(page: 1)
    }

    /// Call from `onAppear` of rows: loads the next page when `item` is within the last 5.
    public func loadMoreIfNeeded(currentItem item: Item) async {
        guard state != .loadingMore, state != .loading, state != .exhausted else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }), index >= items.count - 5 else { return }
        state = .loadingMore
        await load(page: nextPage)
    }

    private func load(page: Int) async {
        let task = Task { [fetch] in
            try await fetch(page)
        }
        current = Task { _ = await task.result }
        do {
            let response = try await task.value
            var fresh = items
            for item in response.data where !seen.contains(item.id) {
                seen.insert(item.id)
                fresh.append(item)
            }
            items = fresh
            meta = response.meta
            nextPage = page + 1
            state = (response.pagination?.hasNextPage ?? false) ? .idle : .exhausted
        } catch let error as APIError where error == .cancelled {
            // A newer load superseded this one; keep whatever it produces.
        } catch let error as APIError {
            state = .failed(error)
        } catch {
            state = .failed(.network(code: -1))
        }
    }

    public var isEmpty: Bool {
        items.isEmpty && (state == .exhausted || state == .idle)
    }
}
