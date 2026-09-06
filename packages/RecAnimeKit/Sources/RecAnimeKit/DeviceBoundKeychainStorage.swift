import Auth
import Foundation
import RecAnimeCore
import Security

/// The Keychain calls `DeviceBoundKeychainStorage` needs, as a seam: the real implementation talks
/// to the Security framework, the tests use an in-memory fake.
public protocol KeychainClient: Sendable {
    func add(_ query: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func copy(_ query: [String: Any]) -> (status: OSStatus, data: Data?)
    func delete(_ query: [String: Any]) -> OSStatus
}

/// `KeychainClient` backed by the Security framework.
public struct SystemKeychainClient: KeychainClient {
    public init() {}

    public func add(_ query: [String: Any]) -> OSStatus {
        SecItemAdd(query as CFDictionary, nil)
    }

    public func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    public func copy(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    public func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

/// A Keychain operation that failed with something other than "item not found".
public struct KeychainStorageError: LocalizedError, Equatable {
    public let status: OSStatus

    public init(status: OSStatus) {
        self.status = status
    }

    public var errorDescription: String? {
        "Keychain operation failed with OSStatus \(status)."
    }
}

/// `AuthLocalStorage` that keeps the Supabase session on this device only.
///
/// The SDK's own `KeychainLocalStorage` writes with `kSecAttrAccessibleAfterFirstUnlock`, which an
/// encrypted backup can restore onto a different device. The item layout matches it exactly
/// (generic password, `kSecAttrService` = service, `kSecAttrAccount` = key) so a session written by
/// the previous storage is still found; only the accessibility changes, and `store` rewrites the
/// item so the upgrade happens on the next save. `kSecUseDataProtectionKeychain` is a no-op on iOS
/// and watchOS, where this runs, and keeps macOS test hosts off the legacy file-based keychain.
public final class DeviceBoundKeychainStorage: AuthLocalStorage, Sendable {
    private let service: String
    private let client: any KeychainClient

    public init(
        service: String = Identifiers.keychainService,
        client: any KeychainClient = SystemKeychainClient()
    ) {
        self.service = service
        self.client = client
    }

    public func store(key: String, value: Data) throws {
        // Delete-then-add rather than update: adding is the only way to change the accessibility of
        // an item the old storage wrote under the same service and account.
        _ = client.delete(baseQuery(for: key))
        var query = baseQuery(for: key)
        query[kSecValueData as String] = value
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = client.add(query)
        // The delete cannot reach an item in another access group; updating it still upgrades the
        // accessibility, so it is a better fallback than failing the sign-in.
        if status == errSecDuplicateItem {
            let updated = client.update(baseQuery(for: key), attributes: [
                kSecValueData as String: value,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ])
            try check(updated)
            return
        }
        try check(status)
    }

    public func retrieve(key: String) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = client.copy(query)
        if status == errSecItemNotFound {
            return nil
        }
        try check(status)
        return data
    }

    public func remove(key: String) throws {
        let status = client.delete(baseQuery(for: key))
        if status == errSecItemNotFound {
            return
        }
        try check(status)
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw KeychainStorageError(status: status)
        }
    }
}
