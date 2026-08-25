import Foundation
import Observation
import RecAnimeCore

/// Airing schedule of the user's "watching" anime.
@MainActor
@Observable
public final class ScheduleStore {
    public private(set) var items: [ScheduleItem] = []
    public private(set) var lastFetched: Date?
    public private(set) var isStale = false
    public private(set) var lastError: APIError?

    private let api: any RecAnimeAPI
    private var inflight: Task<Void, Never>?

    public init(api: any RecAnimeAPI) {
        self.api = api
    }

    /// Refreshes once even if several callers ask at the same time (launch, notifications, Watch sync).
    public func refresh(includeEpisodes: Bool = false) async {
        if let inflight {
            await inflight.value
            return
        }
        let task = Task { await self.load(includeEpisodes: includeEpisodes) }
        inflight = task
        await task.value
        inflight = nil
    }

    private func load(includeEpisodes: Bool) async {
        do {
            let response = try await api.schedule(includeEpisodes: includeEpisodes)
            items = response.data.sorted { ($0.nextAiringAt ?? .distantFuture) < ($1.nextAiringAt ?? .distantFuture) }
            isStale = response.meta?.stale ?? false
            lastFetched = .now
            lastError = nil
        } catch let error as APIError {
            lastError = error
        } catch {
            lastError = .network(code: -1)
        }
    }

    /// Replaces the items with a snapshot pushed by the iPhone.
    public func replace(with snapshot: [ScheduleItem], generatedAt: Date) {
        items = snapshot.sorted { ($0.nextAiringAt ?? .distantFuture) < ($1.nextAiringAt ?? .distantFuture) }
        lastFetched = generatedAt
    }

    /// Whether a refresh is worth doing (older than `maxAge`).
    public func needsRefresh(maxAge: TimeInterval = 15 * 60, now: Date = .now) -> Bool {
        guard let lastFetched else { return true }
        return now.timeIntervalSince(lastFetched) > maxAge
    }
}
