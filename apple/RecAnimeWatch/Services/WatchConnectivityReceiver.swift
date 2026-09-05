import Foundation
import RecAnimeCore
import RecAnimeKit
import WatchConnectivity
import WidgetKit

/// Watch side of WatchConnectivity: receives the session/snapshot context and complication data.
@MainActor
final class WatchConnectivityReceiver: NSObject {
    /// Minimum delay between two `needsSession` requests.
    private static let sessionRequestInterval: TimeInterval = 30

    private unowned let deps: WatchDependencies
    private var activated = false
    private var pendingSessionRequest = false
    private var lastSessionRequestAt: Date?
    private(set) var lastContextAt: Date?

    init(deps: WatchDependencies) {
        self.deps = deps
        super.init()
    }

    func activate() {
        guard !activated, WCSession.isSupported() else { return }
        activated = true
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Asks the iPhone for a session (reachable → message, otherwise a queued user info transfer).
    /// The application context is never used for requests: the phone does not handle it.
    func requestSession() {
        let session = WCSession.default
        guard activated, session.activationState == .activated else {
            pendingSessionRequest = true
            return
        }
        if let lastSessionRequestAt, Date.now.timeIntervalSince(lastSessionRequestAt) < Self.sessionRequestInterval {
            return
        }
        lastSessionRequestAt = .now
        // The error handler runs off the main actor; rebuild the payload there from Sendable pieces.
        let at = Date.now.timeIntervalSince1970
        let payload: [String: Any] = ["type": WatchMessageType.needsSession.rawValue, "at": at]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in
                // WCSession is thread-safe; fall back to the queued transfer when the message fails.
                WCSession.default.transferUserInfo(["type": WatchMessageType.needsSession.rawValue, "at": at])
            })
        } else {
            session.transferUserInfo(payload)
        }
    }

    func notifyLibraryChanged(malID: Int, episodes: Int) {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(["type": WatchMessageType.libraryChanged.rawValue, "malId": malID, "episodes": episodes])
    }

    /// Decodes and applies a context dictionary (only Sendable pieces cross the actor boundary).
    /// Credentials never travel in the context; they arrive as a `session` user info transfer.
    func apply(type: String?, snapshotData: Data?, devBypass: Bool?) async {
        lastContextAt = .now
        switch WatchMessageType(rawValue: type ?? "") {
        case .signedOut:
            await deps.signOutLocally()
        case .context:
            if let devBypass {
                deps.setDevBypass(devBypass)
            }
            if let snapshotData, let snapshot = try? JSONDecoder.recanime.decode(WatchSnapshot.self, from: snapshotData) {
                deps.apply(snapshot: snapshot)
            }
            await deps.refresh(throttle: true)
        default:
            break
        }
    }

    func applyComplication(data: Data) {
        guard let snapshot = try? JSONDecoder.recanime.decode(ComplicationSnapshot.self, from: data) else { return }
        try? deps.appGroup.write(snapshot, file: AppGroupStore.complicationFile)
        WidgetCenter.shared.reloadTimelines(ofKind: Identifiers.nextEpisodeWidgetKind)
    }

    /// Adopts credentials delivered by `transferUserInfo` (queued, exactly once, ordered).
    func applySession(data: Data) async {
        guard let watchSession = try? JSONDecoder.recanime.decode(WatchSession.self, from: data) else { return }
        await deps.adoptSession(watchSession)
    }
}

extension WatchConnectivityReceiver: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        guard activationState == .activated else { return }
        let context = session.receivedApplicationContext
        let type = context["type"] as? String
        let snapshotData = context["snapshot"] as? Data
        let devBypass = context["devBypass"] as? Bool
        Task { @MainActor in
            await apply(type: type, snapshotData: snapshotData, devBypass: devBypass)
            if pendingSessionRequest {
                pendingSessionRequest = false
                requestSession()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let type = applicationContext["type"] as? String
        let snapshotData = applicationContext["snapshot"] as? Data
        let devBypass = applicationContext["devBypass"] as? Bool
        Task { @MainActor in await apply(type: type, snapshotData: snapshotData, devBypass: devBypass) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let type = userInfo["type"] as? String
        let data = userInfo["snapshot"] as? Data
        let sessionData = userInfo["session"] as? Data
        switch type {
        case WatchMessageType.session.rawValue:
            guard let sessionData else { return }
            Task { @MainActor in await applySession(data: sessionData) }
        case WatchMessageType.complication.rawValue:
            guard let data else { return }
            Task { @MainActor in applyComplication(data: data) }
        default:
            break
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        Task { @MainActor in
            guard isReachable, case .signedOut = deps.session?.state else { return }
            requestSession()
        }
    }
}
