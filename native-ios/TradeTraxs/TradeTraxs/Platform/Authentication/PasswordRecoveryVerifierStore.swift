import Foundation

/// Remembers the PKCE verifier for the in-app reset email until the link is opened.
///
/// Stored outside the session keychain service so logout does not erase a reset
/// that has not been opened yet. Cleared after exchange. Never logged.
nonisolated protocol PasswordRecoveryVerifierStoring: Sendable {
    func save(_ verifier: String) throws
    func load() throws -> String?
    func clear() throws
}

nonisolated enum PasswordRecoveryVerifierStore {
    private static let lock = NSLock()
    private static let service = "com.tradetraxs.TradeTraxs.password-recovery"
    private static let account = "codeVerifier"
    nonisolated(unsafe) private static var storage: any PasswordRecoveryVerifierStoring = KeychainPasswordRecoveryVerifierStore()

    static func save(_ verifier: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try storage.save(verifier)
    }

    static func load() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return try storage.load()
    }

    static func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? storage.clear()
    }

    static func replaceForTesting(_ storage: any PasswordRecoveryVerifierStoring) {
        lock.lock()
        defer { lock.unlock() }
        self.storage = storage
    }

    static func useProductionStoreForTesting() {
        lock.lock()
        defer { lock.unlock() }
        storage = KeychainPasswordRecoveryVerifierStore()
    }
}

private nonisolated struct KeychainPasswordRecoveryVerifierStore: PasswordRecoveryVerifierStoring {
    private let keychain: KeychainService = KeychainService()

    func save(_ verifier: String) throws {
        guard let data = verifier.data(using: .utf8) else {
            throw AuthenticationError.keychain("Invalid recovery verifier encoding")
        }
        try keychain.set(data, account: PasswordRecoveryVerifierStore.accountName, service: PasswordRecoveryVerifierStore.serviceName)
    }

    func load() throws -> String? {
        guard let data = try keychain.data(
            account: PasswordRecoveryVerifierStore.accountName,
            service: PasswordRecoveryVerifierStore.serviceName
        ) else {
            return nil
        }
        let verifier = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return verifier.isEmpty ? nil : verifier
    }

    func clear() throws {
        try keychain.delete(
            account: PasswordRecoveryVerifierStore.accountName,
            service: PasswordRecoveryVerifierStore.serviceName
        )
    }
}

nonisolated extension PasswordRecoveryVerifierStore {
    static var serviceName: String { service }
    static var accountName: String { account }
}
