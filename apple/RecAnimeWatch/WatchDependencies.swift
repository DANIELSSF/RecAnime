import Foundation
import Observation
import RecAnimeCore
import RecAnimeKit
import WatchKit
import WidgetKit

/// Composition root of the Watch app.
@MainActor
@Observable
final class WatchDependencies {
    static let shared = WatchDependencies()
    private static let devBypassKey = "ra.watch.devBypass"
    private static let lastAdoptedMintedAtKey = "ra.watch.lastAdoptedMintedAt"

    let config: AppConfig
    let session: SessionStore?
    let api: any RecAnimeAPI
    let library: LibraryStore
    let schedule: ScheduleStore
    let outbox = EpisodeOutbox()
    let appGroup = AppGroupStore()
    private(set) var connectivity: WatchConnectivityReceiver!
    /// Set from the iPhone's context when the API runs with DEV_BYPASS_AUTH (no Supabase configured).
    private(set) var devBypass: Bool
    private(set) var lastRefresh: Date?
    private(set) var lastError: String?
    /// `mintedAt` of the last session adopted from the iPhone; older payloads are ignored.
    private(set) var lastAdoptedMintedAt: Date?

    init(config: AppConfig = AppConfig.load()) {
        self.config = config
        devBypass = UserDefaults.standard.bool(forKey: Self.devBypassKey)
        lastAdoptedMintedAt = UserDefaults.standard.object(forKey: Self.lastAdoptedMintedAtKey) as? Date
        let tokenProvider: any TokenProvider
        let client: APIClient
        if config.hasAuthConfiguration, let url = config.supabaseURL {
            let store = SessionStore(auth: SupabaseAuthFactory.makeClient(url: url, publishableKey: config.supabasePublishableKey))
            session = store
            tokenProvider = store.tokenProvider
            // Capture the store, not self: `self` is not fully initialised yet.
            let onAccessRevoked: AccessRevokedHandler = { reason in await store.revoke(reason) }
            client = APIClient(baseURL: config.apiBaseURL, tokenProvider: tokenProvider, onAccessRevoked: onAccessRevoked)
        } else {
            session = nil
            tokenProvider = WatchDevTokenProvider()
            client = APIClient(baseURL: config.apiBaseURL, tokenProvider: tokenProvider, onAccessRevoked: nil)
        }
        api = LiveRecAnimeAPI(client: client)
        library = LibraryStore(api: api, debounce: .zero)
        schedule = ScheduleStore(api: api)
        connectivity = WatchConnectivityReceiver(deps: self)
        session?.bootstrap()
        if let snapshot = appGroup.read(WatchSnapshot.self, file: AppGroupStore.snapshotFile) {
            library.applySnapshot(snapshot.watching)
            schedule.replace(with: snapshot.schedule, generatedAt: snapshot.generatedAt)
        }
    }

    /// Whether the app can call the API (a session exists, or the API does not require one).
    var canUseAPI: Bool {
        if session == nil {
            return true
        } // no Supabase configured at build time → dev bypass build
        if case .signedIn = session?.state {
            return true
        }
        return false
    }

    func setDevBypass(_ value: Bool) {
        devBypass = value
        UserDefaults.standard.set(value, forKey: Self.devBypassKey)
    }

    /// Pulls fresh data, replays queued episode changes and refreshes the complication.
    func refresh(throttle: Bool) async {
        guard canUseAPI else { return }
        if throttle, let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < 120 {
            return
        }
        let replayError = await outbox.replay(api: api)
        await library.load()
        await schedule.refresh()
        if let error = library.lastError ?? schedule.lastError {
            lastError = error.userMessage
        } else {
            // The fetch worked but queued episode changes are still stuck: say so instead of nothing.
            lastError = Self.pendingOutboxMessage(for: replayError)
            lastRefresh = .now
            persistSnapshot()
        }
        Self.scheduleBackgroundRefresh()
    }

    /// Records an episode as watched: local first, then the API (queued when offline).
    func markEpisode(_ item: RecAnimeCore.LibraryItem, delta: Int) async {
        WKInterfaceDevice.current().play(.click)
        let target = max(item.entry.episodesWatched + delta, 0)
        library.increment(for: item.anime, by: delta)
        await library.flush()
        if let error = library.lastError, error != .cancelled {
            outbox.enqueue(malID: item.anime.malId, target: target)
            switch error {
            case .network:
                lastError = "Sin conexión: se enviará más tarde."
            case .unauthorized:
                lastError = "Sesión caducada: se enviará al reconectar."
            default:
                lastError = "No se pudo guardar: se reintentará."
            }
            WKInterfaceDevice.current().play(.failure)
        } else {
            lastError = nil
            connectivity.notifyLibraryChanged(malID: item.anime.malId, episodes: target)
        }
        persistSnapshot()
    }

    /// Applies data pushed by the iPhone.
    func apply(snapshot: WatchSnapshot) {
        library.applySnapshot(snapshot.watching)
        schedule.replace(with: snapshot.schedule, generatedAt: snapshot.generatedAt)
        persistSnapshot()
    }

    /// Adopts credentials minted by the iPhone. Older or already-adopted payloads are ignored so a
    /// replayed transfer cannot reuse a refresh token the Watch has already rotated.
    func adoptSession(_ watchSession: WatchSession) async {
        if let lastAdoptedMintedAt, watchSession.mintedAt <= lastAdoptedMintedAt {
            return
        }
        do {
            try await session?.adopt(watchSession)
            lastAdoptedMintedAt = watchSession.mintedAt
            UserDefaults.standard.set(watchSession.mintedAt, forKey: Self.lastAdoptedMintedAtKey)
            lastError = nil
            await refresh(throttle: false)
        } catch {
            lastError = "No se pudo activar la sesión del reloj."
        }
    }

    func signOutLocally() async {
        await session?.signOut(scope: .local)
        outbox.clear()
        lastAdoptedMintedAt = nil
        UserDefaults.standard.removeObject(forKey: Self.lastAdoptedMintedAtKey)
        library.clear()
        schedule.replace(with: [], generatedAt: .now)
        persistSnapshot()
    }

    private func persistSnapshot() {
        let snapshot = WatchSnapshot(watching: library.groups.watching, schedule: schedule.items, generatedAt: .now)
        try? appGroup.write(snapshot, file: AppGroupStore.snapshotFile)
        ComplicationSnapshotWriter.write(schedule: schedule.items, store: appGroup)
    }

    /// Hint shown when the data is fresh but the outbox could not be drained.
    private static func pendingOutboxMessage(for error: APIError?) -> String? {
        guard let error else { return nil }
        switch error {
        case .network, .unauthorized: return "Cambios pendientes de enviar."
        default: return nil
        }
    }

    static func scheduleBackgroundRefresh() {
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: Date(timeIntervalSinceNow: 3600), userInfo: nil) { _ in }
    }
}

struct WatchDevTokenProvider: TokenProvider {
    func accessToken() async throws -> String {
        "dev-bypass"
    }

    func forceRefresh() async throws -> String {
        "dev-bypass"
    }
}
