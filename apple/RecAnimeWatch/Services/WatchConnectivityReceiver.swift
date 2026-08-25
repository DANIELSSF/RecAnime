import Foundation
import RecAnimeCore
import RecAnimeKit
import WatchConnectivity
import WidgetKit

/// Watch side of WatchConnectivity: receives the session/snapshot context and complication data.
@MainActor
final class WatchConnectivityReceiver: NSObject {
    private unowned let deps: WatchDependencies
    private var activated = false
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

    /// Asks the iPhone for a session (reachable → message, otherwise our own context).
    func requestSession() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let payload: [String: Any] = ["type": WatchMessageType.needsSession.rawValue, "at": Date.now.timeIntervalSince1970]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            try? session.updateApplicationContext(payload)
        }
    }

    func notifyLibraryChanged(malID: Int, episodes: Int) {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(["type": WatchMessageType.libraryChanged.rawValue, "malId": malID, "episodes": episodes])
    }

    /// Decodes and applies a context dictionary (only Sendable pieces cross the actor boundary).
    func apply(type: String?, sessionData: Data?, snapshotData: Data?, devBypass: Bool?) async {
        lastContextAt = .now
        switch WatchMessageType(rawValue: type ?? "") {
        case .signedOut:
            await deps.signOutLocally()
        case .context:
            if let devBypass {
                deps.setDevBypass(devBypass)
            }
            if let sessionData, let watchSession = try? JSONDecoder.recanime.decode(WatchSession.self, from: sessionData) {
                try? await deps.session?.adopt(watchSession)
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
}

extension WatchConnectivityReceiver: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        guard activationState == .activated else { return }
        let context = session.receivedApplicationContext
        let type = context["type"] as? String
        let sessionData = context["session"] as? Data
        let snapshotData = context["snapshot"] as? Data
        let devBypass = context["devBypass"] as? Bool
        Task { @MainActor in
            await apply(type: type, sessionData: sessionData, snapshotData: snapshotData, devBypass: devBypass)
            if type == nil {
                requestSession()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let type = applicationContext["type"] as? String
        let sessionData = applicationContext["session"] as? Data
        let snapshotData = applicationContext["snapshot"] as? Data
        let devBypass = applicationContext["devBypass"] as? Bool
        Task { @MainActor in await apply(type: type, sessionData: sessionData, snapshotData: snapshotData, devBypass: devBypass) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard userInfo["type"] as? String == WatchMessageType.complication.rawValue, let data = userInfo["snapshot"] as? Data else { return }
        Task { @MainActor in applyComplication(data: data) }
    }
}
