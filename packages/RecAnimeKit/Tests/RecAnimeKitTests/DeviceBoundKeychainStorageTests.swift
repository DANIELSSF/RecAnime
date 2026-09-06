import Foundation
@testable import RecAnimeKit
import Security
import Testing

/// In-memory `KeychainClient`. Items are keyed by service + account, the way the real Keychain keys
/// a generic password, and every query is recorded so the tests can assert the attributes.
private final class FakeKeychainClient: KeychainClient, @unchecked Sendable {
    struct ItemKey: Hashable {
        let service: String
        let account: String
    }

    private let lock = NSLock()
    private var items: [ItemKey: Data] = [:]
    private var addedQueries: [[String: Any]] = []
    private var deletesAreNoOps = false
    private var failure: OSStatus?

    var adds: [[String: Any]] {
        lock.withLock { addedQueries }
    }

    var itemCount: Int {
        lock.withLock { items.count }
    }

    /// Simulates an item this client cannot reach with a delete (a different access group), which
    /// is what makes `SecItemAdd` answer `errSecDuplicateItem`.
    func ignoreDeletes() {
        lock.withLock { deletesAreNoOps = true }
    }

    /// Makes every subsequent operation fail with `status`.
    func failEverything(with status: OSStatus) {
        lock.withLock { failure = status }
    }

    func add(_ query: [String: Any]) -> OSStatus {
        lock.withLock {
            addedQueries.append(query)
            if let failure {
                return failure
            }
            guard let data = query[kSecValueData as String] as? Data else { return errSecParam }
            let key = Self.itemKey(query)
            if items[key] != nil {
                return errSecDuplicateItem
            }
            items[key] = data
            return errSecSuccess
        }
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            if let failure {
                return failure
            }
            let key = Self.itemKey(query)
            guard items[key] != nil else { return errSecItemNotFound }
            guard let data = attributes[kSecValueData as String] as? Data else { return errSecParam }
            items[key] = data
            return errSecSuccess
        }
    }

    func copy(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        lock.withLock {
            if let failure {
                return (failure, nil)
            }
            guard let data = items[Self.itemKey(query)] else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, data)
        }
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lock.withLock {
            if let failure {
                return failure
            }
            if deletesAreNoOps {
                return errSecSuccess
            }
            guard items.removeValue(forKey: Self.itemKey(query)) != nil else { return errSecItemNotFound }
            return errSecSuccess
        }
    }

    private static func itemKey(_ query: [String: Any]) -> ItemKey {
        ItemKey(
            service: query[kSecAttrService as String] as? String ?? "",
            account: query[kSecAttrAccount as String] as? String ?? ""
        )
    }
}

@Suite("DeviceBoundKeychainStorage")
struct DeviceBoundKeychainStorageTests {
    private let service = "com.example.tests.auth"

    private func makeStorage() -> (DeviceBoundKeychainStorage, FakeKeychainClient) {
        let client = FakeKeychainClient()
        return (DeviceBoundKeychainStorage(service: service, client: client), client)
    }

    @Test("a stored value comes back unchanged")
    func roundTrip() throws {
        let (storage, _) = makeStorage()
        try storage.store(key: "session", value: Data("token".utf8))
        #expect(try storage.retrieve(key: "session") == Data("token".utf8))
    }

    @Test("storing twice replaces the value instead of adding a second item")
    func overwrite() throws {
        let (storage, client) = makeStorage()
        try storage.store(key: "session", value: Data("first".utf8))
        try storage.store(key: "session", value: Data("second".utf8))
        #expect(try storage.retrieve(key: "session") == Data("second".utf8))
        #expect(client.itemCount == 1)
    }

    @Test("remove deletes the item")
    func remove() throws {
        let (storage, _) = makeStorage()
        try storage.store(key: "session", value: Data("token".utf8))
        try storage.remove(key: "session")
        #expect(try storage.retrieve(key: "session") == nil)
    }

    @Test("a missing key reads as nil and removes without throwing")
    func missingKey() throws {
        let (storage, _) = makeStorage()
        #expect(try storage.retrieve(key: "absent") == nil)
        try storage.remove(key: "absent")
    }

    @Test("the item is written this-device-only, in the data-protection keychain")
    func addQueryAttributes() throws {
        let (storage, client) = makeStorage()
        try storage.store(key: "session", value: Data("token".utf8))
        let query = try #require(client.adds.first)
        #expect(query[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
    }

    @Test("the item layout matches the SDK's own storage, so existing sessions are still found")
    func addQueryLayout() throws {
        let (storage, client) = makeStorage()
        try storage.store(key: "session", value: Data("token".utf8))
        let query = try #require(client.adds.first)
        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == service)
        #expect(query[kSecAttrAccount as String] as? String == "session")
    }

    @Test("an item the delete cannot reach is upgraded through update")
    func duplicateItemFallsBackToUpdate() throws {
        let (storage, client) = makeStorage()
        try storage.store(key: "session", value: Data("first".utf8))
        client.ignoreDeletes()
        try storage.store(key: "session", value: Data("second".utf8))
        #expect(try storage.retrieve(key: "session") == Data("second".utf8))
        #expect(client.itemCount == 1)
    }

    @Test("a Keychain failure surfaces as an error instead of silently losing the session")
    func failuresThrow() {
        let (storage, client) = makeStorage()
        client.failEverything(with: errSecNotAvailable)
        #expect(throws: KeychainStorageError(status: errSecNotAvailable)) {
            try storage.store(key: "session", value: Data("token".utf8))
        }
        #expect(throws: KeychainStorageError(status: errSecNotAvailable)) {
            try storage.retrieve(key: "session")
        }
        #expect(throws: KeychainStorageError(status: errSecNotAvailable)) {
            try storage.remove(key: "session")
        }
    }
}
