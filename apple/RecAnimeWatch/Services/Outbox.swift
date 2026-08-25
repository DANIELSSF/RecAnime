import Foundation
import RecAnimeCore
import RecAnimeKit

/// Episode updates made offline; replayed with absolute values so duplicates are harmless.
@MainActor
final class Outbox {
    private static let key = "ra.watch.outbox"
    private var targets: [Int: Int]

    init() {
        let raw = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: Int] ?? [:]
        targets = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in Int(key).map { ($0, value) } })
    }

    var isEmpty: Bool {
        targets.isEmpty
    }

    func isPending(_ malID: Int) -> Bool {
        targets[malID] != nil
    }

    func enqueue(malID: Int, target: Int) {
        targets[malID] = target
        persist()
    }

    func replay(api: any RecAnimeAPI) async {
        for (malID, target) in targets {
            do {
                _ = try await api.adjustEpisodes(malID, .set(target))
                targets.removeValue(forKey: malID)
            } catch let error as APIError where error.isRetryable || error == .cancelled {
                continue // keep queued
            } catch {
                targets.removeValue(forKey: malID) // permanent failure: drop
            }
        }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: targets.map { (String($0.key), $0.value) }), forKey: Self.key)
    }
}
