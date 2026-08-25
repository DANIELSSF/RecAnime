import Foundation
import Observation
import RecAnimeCore
import RecAnimeKit
import WatchConnectivity

/// iPhone side of WatchConnectivity: ships a dedicated Supabase session plus a data snapshot to the
/// Watch (application context, latest wins) and reacts to the Watch's requests.
@MainActor
@Observable
final class PhoneWatchSync: NSObject {
    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false
    private(set) var isReachable = false
    private(set) var lastSyncAt: Date?
    private(set) var lastError: String?

    private let config: AppConfig
    private let library: LibraryStore
    private let schedule: ScheduleStore
    private let notifications: NotificationCoordinator
    private var lastMintedSession: WatchSession?
    private var activated = false

    init(config: AppConfig, library: LibraryStore, schedule: ScheduleStore, notifications: NotificationCoordinator) {
        self.config = config
        self.library = library
        self.schedule = schedule
        self.notifications = notifications
        super.init()
    }

    func activate() {
        guard !activated, WCSession.isSupported() else { return }
        activated = true
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Creates an independent session for the Watch from fresh Google tokens (refresh tokens rotate,
    /// so the Watch must never share the phone's session).
    func mintSession(idToken: String, accessToken: String?) async {
        guard let supabaseURL = config.supabaseURL else { return }
        let minter = SupabaseAuthFactory.makeMinter(url: supabaseURL, publishableKey: config.supabasePublishableKey)
        do {
            let session = try await minter.signInWithIdToken(credentials: .init(provider: .google, idToken: idToken, accessToken: accessToken))
            lastMintedSession = session.watchSession
            lastError = nil
            await pushSnapshot()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Silent re-mint using the Google SDK's restored user (Watch asked, or "Sincronizar ahora").
    func remintSilently() async {
        do {
            let tokens = try await GoogleSignInCoordinator.refreshedTokens()
            await mintSession(idToken: tokens.idToken, accessToken: tokens.accessToken)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Sends the latest context: session (if any), dev-bypass flag, watching list and schedule.
    func pushSnapshot() async {
        guard activated, WCSession.default.activationState == .activated else { return }
        if schedule.needsRefresh() {
            await schedule.refresh()
        }
        let snapshot = WatchSnapshot(watching: library.groups.watching, schedule: schedule.items, generatedAt: .now)
        var context: [String: Any] = [
            "type": WatchMessageType.context.rawValue,
            "generatedAt": Date.now.timeIntervalSince1970,
            "devBypass": !config.hasAuthConfiguration,
            "apiBaseURL": config.apiBaseURL.absoluteString,
        ]
        if let data = try? JSONEncoder.recanime.encode(snapshot) {
            context["snapshot"] = data
        }
        if let session = lastMintedSession, let data = try? JSONEncoder.recanime.encode(session) {
            context["session"] = data
        }
        do {
            try WCSession.default.updateApplicationContext(context)
            lastSyncAt = .now
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        pushComplication()
    }

    /// Complication data goes through the dedicated (budgeted) transfer so the face updates promptly.
    private func pushComplication() {
        let session = WCSession.default
        guard session.isComplicationEnabled || session.isWatchAppInstalled else { return }
        let snapshot = ComplicationSnapshot.from(schedule: schedule.items, now: .now)
        guard let data = try? JSONEncoder.recanime.encode(snapshot) else { return }
        let payload: [String: Any] = ["type": WatchMessageType.complication.rawValue, "snapshot": data]
        if session.isComplicationEnabled, session.remainingComplicationUserInfoTransfers > 0 {
            session.transferCurrentComplicationUserInfo(payload)
        } else {
            session.transferUserInfo(payload)
        }
    }

    func sendSignedOut() {
        lastMintedSession = nil
        guard activated, WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext(["type": WatchMessageType.signedOut.rawValue, "at": Date.now.timeIntervalSince1970])
    }

    private func refreshState() {
        let session = WCSession.default
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        isReachable = session.isReachable
    }
}

extension PhoneWatchSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        let activated = activationState == .activated
        Task { @MainActor in
            refreshState()
            if activated {
                await pushSnapshot()
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let installed = session.isWatchAppInstalled
        Task { @MainActor in
            refreshState()
            if installed {
                await pushSnapshot()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in refreshState() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        Task { @MainActor in await handle(type: type) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let type = userInfo["type"] as? String else { return }
        Task { @MainActor in await handle(type: type) }
    }

    private func handle(type: String) async {
        switch WatchMessageType(rawValue: type) {
        case .needsSession:
            if lastMintedSession != nil {
                await pushSnapshot()
            } else if config.hasAuthConfiguration {
                await remintSilently()
            } else {
                await pushSnapshot() // dev bypass: the flag in the context is enough
            }
        case .libraryChanged:
            await library.load()
            notifications.scheduleReplan()
            await pushSnapshot()
        default:
            break
        }
    }
}
