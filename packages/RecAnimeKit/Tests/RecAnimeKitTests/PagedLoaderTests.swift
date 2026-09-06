import Foundation
@testable import RecAnimeCore
@testable import RecAnimeKit
import Testing

/// Gate for fetch closures: they announce they started and block until the test releases them.
actor FetchGate {
    private var calls = 0
    private var started = false
    private var released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var holdWaiters: [CheckedContinuation<Void, Never>] = []

    /// Registers a call and answers with its 1-based index.
    func begin() -> Int {
        calls += 1
        if !started {
            started = true
            for waiter in startWaiters {
                waiter.resume()
            }
            startWaiters = []
        }
        return calls
    }

    func waitForStart() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    /// Suspends the caller until `release()`. Deliberately not cancellation-aware: the point is a
    /// fetch that keeps running after its loader gave up on it.
    func hold() async {
        guard !released else { return }
        await withCheckedContinuation { holdWaiters.append($0) }
    }

    func release() {
        released = true
        for waiter in holdWaiters {
            waiter.resume()
        }
        holdWaiters = []
    }
}

/// Records the pages a fetch closure was asked for; the closure runs off the main actor.
final class PageLog: @unchecked Sendable {
    private let lock = NSLock()
    private var pages: [Int] = []

    func record(_ page: Int) {
        lock.withLock { pages.append(page) }
    }

    var recorded: [Int] {
        lock.withLock { pages }
    }

    var count: Int {
        recorded.count
    }
}

/// Three summaries whose ids come from the page the server says it served.
private func pageResponse(_ page: Int, served: Int? = nil, hasNext: Bool = true) -> APIResponse<[AnimeSummary]> {
    let served = served ?? page
    return APIResponse(
        data: (0 ..< 3).map { FakeAPI.sample(served * 10 + $0).anime },
        pagination: Pagination(page: served, perPage: 3, hasNextPage: hasNext, lastVisiblePage: 9, total: 27)
    )
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
        #expect(loader.lastLoadedAt == nil)
    }

    @Test("a superseded fetch never leaks into the new list")
    func supersededFetchIsDropped() async {
        let gate = FetchGate()
        let loader = PagedLoader<AnimeSummary> { page in
            if await gate.begin() == 1 {
                await gate.hold()
                return APIResponse(
                    data: [FakeAPI.sample(999).anime],
                    pagination: Pagination(page: page, perPage: 3, hasNextPage: true, lastVisiblePage: 9, total: 27)
                )
            }
            return pageResponse(1, hasNext: false)
        }
        let stale = Task { await loader.loadFirst() }
        await gate.waitForStart()
        await loader.loadFirst() // cancels the gated fetch and bumps the generation
        #expect(loader.items.map(\.id) == [10, 11, 12])
        #expect(loader.state == .exhausted)

        await gate.release() // the abandoned fetch finishes now
        await stale.value
        #expect(loader.items.map(\.id) == [10, 11, 12])
        #expect(loader.state == .exhausted)
        #expect(loader.lastLoadedAt != nil)
    }

    @Test("a failed page is never retried on its own; retryMore is the way back")
    func noAutoRetryAfterFailure() async {
        let log = PageLog()
        let loader = PagedLoader<AnimeSummary> { page in
            log.record(page)
            if page == 2, log.recorded.filter({ $0 == 2 }).count == 1 {
                throw APIError.server(status: 502, code: "upstream_unavailable", message: nil)
            }
            return pageResponse(page)
        }
        await loader.loadFirst()
        #expect(loader.items.count == 3)
        await loader.loadMoreIfNeeded(currentItem: loader.items[2])
        #expect(loader.state == .failed(.server(status: 502, code: "upstream_unavailable", message: nil)))
        #expect(log.recorded == [1, 2])

        // Rows keep appearing while the footer shows the error: nothing must go out.
        await loader.loadMoreIfNeeded(currentItem: loader.items[2])
        await loader.loadMoreIfNeeded(currentItem: loader.items[0])
        #expect(log.recorded == [1, 2])

        await loader.retryMore()
        #expect(log.recorded == [1, 2, 2])
        #expect(loader.items.count == 6)
        #expect(loader.state == .idle)
    }

    @Test("retryMore reloads from scratch when the first page failed")
    func retryMoreReloadsEmptyLoader() async {
        let log = PageLog()
        let loader = PagedLoader<AnimeSummary> { page in
            log.record(page)
            if log.count == 1 {
                throw APIError.network(code: -1009)
            }
            return pageResponse(page, hasNext: false)
        }
        await loader.loadFirst()
        #expect(loader.state == .failed(.network(code: -1009)))
        #expect(loader.items.isEmpty)

        await loader.retryMore()
        #expect(log.recorded == [1, 1])
        #expect(loader.items.count == 3)
        #expect(loader.state == .exhausted)
    }

    @Test("the next page follows the page the server reports")
    func nextPageFollowsPagination() async {
        let log = PageLog()
        let loader = PagedLoader<AnimeSummary> { page in
            log.record(page)
            // The server skipped forward past fully filtered pages: it served page 4 for request 1.
            return pageResponse(page, served: page == 1 ? 4 : page)
        }
        await loader.loadFirst()
        #expect(loader.items.map(\.id) == [40, 41, 42])
        await loader.loadMoreIfNeeded(currentItem: loader.items[2])
        #expect(log.recorded == [1, 5])
        #expect(loader.items.count == 6)
    }

    @Test("seed hydrates an idle loader and loadFirst replaces it")
    func seedThenLoadFirst() async {
        let loader = PagedLoader<AnimeSummary> { page in pageResponse(page, hasNext: false) }
        loader.seed([FakeAPI.sample(500).anime, FakeAPI.sample(501).anime, FakeAPI.sample(500).anime])
        #expect(loader.items.map(\.id) == [500, 501]) // duplicates inside the snapshot are dropped
        #expect(loader.state == .idle)
        #expect(loader.lastLoadedAt == nil)
        #expect(loader.isEmpty == false)

        loader.seed([FakeAPI.sample(600).anime]) // already hydrated: ignored
        #expect(loader.items.count == 2)

        await loader.loadFirst()
        #expect(loader.items.map(\.id) == [10, 11, 12])
        #expect(loader.lastLoadedAt != nil)
    }

    @Test("a failed first page keeps the seeded rows; retryMore then reloads from scratch")
    func failedFirstPageKeepsSnapshot() async {
        let log = PageLog()
        let loader = PagedLoader<AnimeSummary> { page in
            log.record(page)
            if log.count == 1 {
                throw APIError.network(code: -1009) // offline cold start
            }
            return pageResponse(page, hasNext: false)
        }
        loader.seed([FakeAPI.sample(500).anime, FakeAPI.sample(501).anime])

        await loader.loadFirst()
        #expect(loader.items.map(\.id) == [500, 501]) // the snapshot stays on screen
        #expect(loader.state == .failed(.network(code: -1009)))
        #expect(loader.lastLoadedAt == nil)

        await loader.retryMore()
        #expect(log.recorded == [1, 1])
        #expect(loader.items.map(\.id) == [10, 11, 12]) // replaced, not appended after the snapshot
        #expect(loader.state == .exhausted)
    }

    @Test("loadFirst replaces a multi-page list instead of appending to it")
    func loadFirstReplaces() async {
        let loader = PagedLoader<AnimeSummary> { page in pageResponse(page) }
        await loader.loadFirst()
        await loader.loadMoreIfNeeded(currentItem: loader.items[2])
        #expect(loader.items.count == 6)

        await loader.loadFirst()
        #expect(loader.items.map(\.id) == [10, 11, 12])
        #expect(loader.state == .idle)
    }

    @Test("replace drops the previous filter's rows even when the new fetch fails")
    func replaceClearsOnFailure() async {
        let loader = PagedLoader<AnimeSummary> { page in pageResponse(page, hasNext: false) }
        await loader.loadFirst()
        #expect(loader.items.count == 3)

        await loader.replace { _ in throw APIError.server(status: 503, code: "upstream_rate_limited", message: nil) }
        #expect(loader.items.isEmpty)
        #expect(loader.state == .failed(.server(status: 503, code: "upstream_rate_limited", message: nil)))
    }
}
