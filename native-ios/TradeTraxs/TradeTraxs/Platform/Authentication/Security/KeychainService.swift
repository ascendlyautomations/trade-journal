import Foundation
import Security

/// Low-level Keychain CRUD. No business logic.
nonisolated protocol KeychainServicing: Sendable {
    func set(_ data: Data, account: String, service: String) throws
    func data(account: String, service: String) throws -> Data?
    func delete(account: String, service: String) throws
    func deleteAll(service: String) throws
}

nonisolated struct KeychainService: KeychainServicing {
    func set(_ data: Data, account: String, service: String) throws {
        try delete(account: account, service: service)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AuthenticationError.keychain("SecItemAdd failed (\(status))")
        }
    }

    func data(account: String, service: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw AuthenticationError.keychain("SecItemCopyMatching failed (\(status))")
        }
        return item as? Data
    }

    func delete(account: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthenticationError.keychain("SecItemDelete failed (\(status))")
        }
    }

    func deleteAll(service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthenticationError.keychain("SecItemDeleteAll failed (\(status))")
        }
    }
}

/// Test / preview store — never used for production secrets on device.
nonisolated final class InMemoryKeychainService: KeychainServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    private func key(account: String, service: String) -> String {
        "\(service)::\(account)"
    }

    func set(_ data: Data, account: String, service: String) throws {
        lock.lock(); storage[key(account: account, service: service)] = data; lock.unlock()
    }

    func data(account: String, service: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key(account: account, service: service)]
    }

    func delete(account: String, service: String) throws {
        lock.lock(); storage.removeValue(forKey: key(account: account, service: service)); lock.unlock()
    }

    func deleteAll(service: String) throws {
        lock.lock()
        storage = storage.filter { !$0.key.hasPrefix("\(service)::") }
        lock.unlock()
    }
}
