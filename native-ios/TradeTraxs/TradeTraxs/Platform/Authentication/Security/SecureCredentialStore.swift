import Foundation

nonisolated protocol SecureCredentialStoring: Sendable {
    func saveSession(_ session: AuthenticationSession) throws
    func loadSession() throws -> AuthenticationSession?
    func clearSession() throws
    func clearAll() throws
}

nonisolated struct SecureCredentialStore: SecureCredentialStoring {
    private let keychain: any KeychainServicing
    private let configuration: AuthenticationConfiguration
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        keychain: any KeychainServicing,
        configuration: AuthenticationConfiguration
    ) {
        self.keychain = keychain
        self.configuration = configuration
    }

    func saveSession(_ session: AuthenticationSession) throws {
        let data = try encoder.encode(session)
        try keychain.set(
            data,
            account: configuration.sessionAccount,
            service: configuration.keychainService
        )
        if let access = session.accessToken.data(using: .utf8) {
            try keychain.set(
                access,
                account: configuration.accessTokenAccount,
                service: configuration.keychainService
            )
        }
        if let refresh = session.refreshToken?.data(using: .utf8) {
            try keychain.set(
                refresh,
                account: configuration.refreshTokenAccount,
                service: configuration.keychainService
            )
        }
    }

    func loadSession() throws -> AuthenticationSession? {
        guard let data = try keychain.data(
            account: configuration.sessionAccount,
            service: configuration.keychainService
        ) else {
            return nil
        }
        return try decoder.decode(AuthenticationSession.self, from: data)
    }

    func clearSession() throws {
        try keychain.delete(account: configuration.sessionAccount, service: configuration.keychainService)
        try keychain.delete(account: configuration.accessTokenAccount, service: configuration.keychainService)
        try keychain.delete(account: configuration.refreshTokenAccount, service: configuration.keychainService)
    }

    func clearAll() throws {
        try keychain.deleteAll(service: configuration.keychainService)
    }
}
