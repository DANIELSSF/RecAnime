import Foundation
import Network
import Observation

/// Network reachability for the offline banner and the "back online" refresh.
///
/// `NWPathMonitor` delivers its updates on a background queue, so the handler only reads a
/// `Sendable` verdict out of the path and hops to the main actor to publish it.
@MainActor
@Observable
final class ConnectivityMonitor {
    /// Optimistic default: the first path update lands within milliseconds of `start()`, and
    /// starting "offline" would flash the banner on every launch.
    private(set) var isOnline = true

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let queue = DispatchQueue(label: "app.recanime.connectivity", qos: .utility)
    @ObservationIgnored private var isStarted = false

    /// Idempotent: the app calls it on launch and on every return to the foreground.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.apply(online)
            }
        }
        monitor.start(queue: queue)
    }

    private func apply(_ online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
    }
}
