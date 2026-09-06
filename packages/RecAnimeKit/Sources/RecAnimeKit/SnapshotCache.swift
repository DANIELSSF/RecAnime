import Foundation
import RecAnimeCore

/// Small on-disk JSON cache so a cold start renders last-known data while the network loads.
/// An actor: every file operation runs off the main actor, and concurrent readers/writers of the
/// same key are serialised.
public actor SnapshotCache {
    public let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "recanime-snapshots")
    }

    /// The stored value, or `nil` when it is missing, corrupt, or older than `maxAge` by file date.
    public func load<T: Decodable & Sendable>(_ type: T.Type, key: String, maxAge: TimeInterval? = nil) -> T? {
        let file = url(key)
        guard let data = try? Data(contentsOf: file) else { return nil }
        if let maxAge {
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))
            guard let modified = attributes?[.modificationDate] as? Date,
                  Date.now.timeIntervalSince(modified) <= maxAge
            else { return nil }
        }
        return try? JSONDecoder.recanime.decode(type, from: data)
    }

    public func save(_ value: some Encodable & Sendable, key: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder.recanime.encode(value) else { return }
        try? data.write(to: url(key), options: .atomic)
    }

    public func remove(key: String) {
        try? FileManager.default.removeItem(at: url(key))
    }

    public func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func url(_ key: String) -> URL {
        directory.appending(path: key.replacingOccurrences(of: "/", with: "_") + ".json")
    }
}
