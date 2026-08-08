import Foundation

/// Session surface for repositories — no Keychain / Supabase Auth yet.
nonisolated protocol SessionProviding: Sendable {
    var currentUserID: UserID? { get async }
    var accessToken: String? { get async }
}

/// Placeholder session — always signed out until Auth phase.
nonisolated struct PlaceholderSessionProvider: SessionProviding {
    var currentUserID: UserID? { get async { nil } }
    var accessToken: String? { get async { nil } }
}
