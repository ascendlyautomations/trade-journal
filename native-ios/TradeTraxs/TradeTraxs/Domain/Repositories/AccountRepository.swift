import Foundation

/// Self-service account actions — the server determines the target user from the session token.
nonisolated protocol AccountRepository: Sendable {
    func deleteAuthenticatedAccount() async throws
    /// CSV from `GET /api/export-data`. Same file the web Settings export downloads.
    func exportAuthenticatedAccountData() async throws -> Data
}

enum AccountDataExport {
    /// Matches `Content-Disposition` on `GET /api/export-data`.
    static let filename = "tradetrax_data.csv"
}

enum AccountDataExportError: Error, Equatable, Sendable {
    case notAuthenticated
    case failed
}

enum AccountDeletionError: Error, Equatable, Sendable {
    case notAuthenticated
    case serverMessage(String)
}
