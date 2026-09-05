import Foundation
import RecAnimeCore

/// Episode updates the Watch could not send; replayed as absolute values so duplicates are harmless.
/// Survives relaunches through `UserDefaults`.
@MainActor
public final class EpisodeOutbox {
    private let defaults: UserDefaults
    private let key: String
    private var targets: [Int: Int]
    private var isReplaying = false

    public init(defaults: UserDefaults = .standard, key: String = "ra.watch.outbox") {
        self.defaults = defaults
        self.key = key
        let raw = defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
        targets = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in Int(key).map { ($0, value) } })
    }

    public var isEmpty: Bool {
        targets.isEmpty
    }

    public var pendingIDs: Set<Int> {
        Set(targets.keys)
    }

    public func isPending(_ malID: Int) -> Bool {
        targets[malID] != nil
    }

    public func enqueue(malID: Int, target: Int) {
        targets[malID] = target
        persist()
    }

    /// Replays absolute targets. Reentrant calls return immediately. Returns the last error, if any.
    @discardableResult
    public func replay(api: any RecAnimeAPI) async -> APIError? {
        guard !isReplaying else { return nil }
        isReplaying = true
        defer {
            isReplaying = false
            persist()
        }
        var lastError: APIError?
        for (malID, target) in targets {
            do {
                _ = try await api.adjustEpisodes(malID, .set(target))
                // An enqueue during the await wins: only drop the value that was actually sent.
                if targets[malID] == target {
                    targets.removeValue(forKey: malID)
                }
            } catch let error as APIError {
                lastError = error
                if Self.isPermanent(error) {
                    targets.removeValue(forKey: malID)
                }
                if Self.stopsReplay(error) {
                    break
                }
            } catch {
                lastError = .network(code: -1)
                break
            }
        }
        return lastError
    }

    public func clear() {
        targets = [:]
        persist()
    }

    /// The entry can never succeed: the anime is gone (404) or the value is invalid (400/422).
    private static func isPermanent(_ error: APIError) -> Bool {
        guard case let .server(status, _, _) = error else { return false }
        return status == 404 || status == 400 || status == 422
    }

    /// No point hammering the rest of the queue: the network or the session is down.
    private static func stopsReplay(_ error: APIError) -> Bool {
        switch error {
        case .unauthorized, .network: true
        default: false
        }
    }

    private func persist() {
        defaults.set(Dictionary(uniqueKeysWithValues: targets.map { (String($0.key), $0.value) }), forKey: key)
    }
}
