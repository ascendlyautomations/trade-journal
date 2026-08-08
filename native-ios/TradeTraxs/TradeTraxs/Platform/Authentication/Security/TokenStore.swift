import Foundation

nonisolated protocol TokenStoring: Sendable {
    func save(accessToken: String, refreshToken: String?) throws
    func accessToken() throws -> String?
    func refreshToken() throws -> String?
    func clear() throws
}

nonisolated struct TokenStore: TokenStoring {
    private let keychain: any KeychainServicing
    private let configuration: AuthenticationConfiguration

    init(keychain: any KeychainServicing, configuration: AuthenticationConfiguration) {
        self.keychain = keychain
        self.configuration = configuration
    }

    func save(accessToken: String, refreshToken: String?) throws {
        guard let accessData = accessToken.data(using: .utf8) else {
            throw AuthenticationError.keychain("Invalid access token encoding")
        }
        try keychain.set(
            accessData,
            account: configuration.accessTokenAccount,
            service: configuration.keychainService
        )
        if let refreshToken, let refreshData = refreshToken.data(using: .utf8) {
            try keychain.set(
                refreshData,
                account: configuration.refreshTokenAccount,
                service: configuration.keychainService
            )
        }
    }

    func accessToken() throws -> String? {
        guard let data = try keychain.data(
            account: configuration.accessTokenAccount,
            service: configuration.keychainService
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func refreshToken() throws -> String? {
        guard let data = try keychain.data(
            account: configuration.refreshTokenAccount,
            service: configuration.keychainService
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func clear() throws {
        try keychain.delete(account: configuration.accessTokenAccount, service: configuration.keychainService)
        try keychain.delete(account: configuration.refreshTokenAccount, service: configuration.keychainService)
    }
}
