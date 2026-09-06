import Foundation
@testable import RecAnimeCore
@testable import RecAnimeKit
import Testing

@Suite("SnapshotCache")
struct SnapshotCacheTests {
    struct Payload: Codable, Equatable, Sendable {
        var title: String
        var count: Int
        var updatedAt: Date
    }

    static let payload = Payload(title: "Frieren", count: 28, updatedAt: Date(timeIntervalSince1970: 1_700_000_000))

    /// Runs `body` against a cache backed by a throwaway directory.
    func withCache(_ body: (SnapshotCache, URL) async throws -> Void) async throws {
        let directory = URL.temporaryDirectory.appending(path: "recanime-snapshots-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(SnapshotCache(directory: directory), directory)
    }

    @Test("a value survives the round trip; a missing key is nil")
    func roundTrip() async throws {
        try await withCache { cache, _ in
            await cache.save(Self.payload, key: "library")
            #expect(await cache.load(Payload.self, key: "library") == Self.payload)
            #expect(await cache.load(Payload.self, key: "missing") == nil)
        }
    }

    @Test("maxAge drops a file older than the window")
    func maxAgeExpiry() async throws {
        try await withCache { cache, directory in
            await cache.save(Self.payload, key: "season.now")
            #expect(await cache.load(Payload.self, key: "season.now", maxAge: 60) != nil)

            let file = directory.appending(path: "season.now.json").path(percentEncoded: false)
            try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-3600)], ofItemAtPath: file)
            #expect(await cache.load(Payload.self, key: "season.now", maxAge: 60) == nil)
            // Without a window the age is irrelevant: stale data still beats an empty screen.
            #expect(await cache.load(Payload.self, key: "season.now") != nil)
        }
    }

    @Test("corrupt data decodes to nil instead of throwing")
    func corruptFile() async throws {
        try await withCache { cache, directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("not json".utf8).write(to: directory.appending(path: "library.json"))
            #expect(await cache.load(Payload.self, key: "library") == nil)
            #expect(await cache.load(Payload.self, key: "library", maxAge: 3600) == nil)
        }
    }

    @Test("remove drops one key, clear drops the whole directory")
    func removeAndClear() async throws {
        try await withCache { cache, directory in
            await cache.save(Self.payload, key: "a")
            await cache.save(Self.payload, key: "b")

            await cache.remove(key: "a")
            #expect(await cache.load(Payload.self, key: "a") == nil)
            #expect(await cache.load(Payload.self, key: "b") != nil)

            await cache.clear()
            #expect(await cache.load(Payload.self, key: "b") == nil)
            #expect(FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) == false)

            // A save after clear recreates the directory.
            await cache.save(Self.payload, key: "b")
            #expect(await cache.load(Payload.self, key: "b") == Self.payload)
        }
    }

    @Test("keys with slashes stay inside the directory")
    func sanitisedKeys() async throws {
        try await withCache { cache, directory in
            await cache.save(Self.payload, key: "season/2026/summer")
            let file = directory.appending(path: "season_2026_summer.json").path(percentEncoded: false)
            #expect(FileManager.default.fileExists(atPath: file))
            #expect(await cache.load(Payload.self, key: "season/2026/summer") == Self.payload)
        }
    }

    @Test("sanitising \"/\" to \"_\" makes a slashed key collide with the already-underscored one")
    func sanitisedKeyCollision() async throws {
        try await withCache { cache, directory in
            // Both keys sanitise to the same file name; this is the sanitiser's actual behaviour today
            // (production call sites only ever use "." as a separator, so the two never collide in
            // practice), not a claim that a "/" key is kept distinct from an "_" key.
            await cache.save(Self.payload, key: "season/now")
            let file = directory.appending(path: "season_now.json").path(percentEncoded: false)
            #expect(FileManager.default.fileExists(atPath: file))

            var other = Self.payload
            other.title = "Sousou no Frieren"
            await cache.save(other, key: "season_now")
            #expect(await cache.load(Payload.self, key: "season/now") == other)
            #expect(await cache.load(Payload.self, key: "season_now") == other)
        }
    }
}
