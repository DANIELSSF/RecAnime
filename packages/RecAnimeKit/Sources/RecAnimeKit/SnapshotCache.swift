import Foundation
import RecAnimeCore

/// Small on-disk JSON cache so a cold start renders last-known data while the network loads.
public struct SnapshotCache: Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "recanime-snapshots")
    }

    public func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: url(key)) else { return nil }
        return try? JSONDecoder.recanime.decode(type, from: data)
    }

    public func save(_ value: some Encodable, key: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.recanime.encode(value) {
            try? data.write(to: url(key), options: .atomic)
        }
    }

    public func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func url(_ key: String) -> URL {
        directory.appending(path: key.replacingOccurrences(of: "/", with: "_") + ".json")
    }
}
