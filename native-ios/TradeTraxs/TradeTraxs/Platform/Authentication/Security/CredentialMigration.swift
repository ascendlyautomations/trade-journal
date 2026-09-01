import Foundation

/// Migrates credential layout across app versions without exposing secrets.
nonisolated protocol CredentialMigrating: Sendable {
    func migrateIfNeeded() throws
}

nonisolated struct CredentialMigration: CredentialMigrating, @unchecked Sendable {
    private let configuration: AuthenticationConfiguration
    private let defaults: UserDefaults
    private let versionKey = "auth.credentialStoreVersion"
    private let currentVersion = 1

    init(
        configuration: AuthenticationConfiguration,
        defaults: UserDefaults = .standard
    ) {
        self.configuration = configuration
        self.defaults = defaults
    }

    func migrateIfNeeded() throws {
        let stored = defaults.integer(forKey: versionKey)
        guard stored < currentVersion else { return }
        // v1 is the initial Keychain layout — no transform required.
        _ = configuration
        defaults.set(currentVersion, forKey: versionKey)
    }
}
