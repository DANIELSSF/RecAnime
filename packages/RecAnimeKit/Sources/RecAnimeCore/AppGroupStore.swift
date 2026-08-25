import Foundation

/// JSON files in the App Group container, shared between the Watch app and its widget extension.
public struct AppGroupStore: Sendable {
    public enum StoreError: Error {
        case containerUnavailable
    }

    public let groupIdentifier: String

    public init(groupIdentifier: String = Identifiers.appGroup) {
        self.groupIdentifier = groupIdentifier
    }

    public func url(for file: String) throws -> URL {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            throw StoreError.containerUnavailable
        }
        return base.appendingPathComponent(file)
    }

    public func read<T: Decodable>(_ type: T.Type, file: String) -> T? {
        guard let url = try? url(for: file), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.recanime.decode(type, from: data)
    }

    public func write(_ value: some Encodable, file: String) throws {
        let url = try url(for: file)
        let data = try JSONEncoder.recanime.encode(value)
        try data.write(to: url, options: .atomic)
    }

    public static let complicationFile = "complication.json"
    public static let snapshotFile = "watch-snapshot.json"
}
