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

    public init(api: any RecAnimeAPI) {
        self.api = api
    }

    public func refresh(includeEpisodes: Bool = false) async {
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

    /// Whether a refresh is worth doing (older than `maxAge`).
    public func needsRefresh(maxAge: TimeInterval = 15 * 60, now: Date = .now) -> Bool {
        guard let lastFetched else { return true }
        return now.timeIntervalSince(lastFetched) > maxAge
    }
}
