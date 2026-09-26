import Foundation

/// Owner Settings → Profile save payload (username change limits + profile fields).
nonisolated struct ProfileSettingsUpdate: Sendable, Equatable {
    var profileID: ProfileID
    var displayName: String
    var bio: String?
    var tradingStyle: String?
    var primaryMarket: String?
    var isPrivate: Bool
    var username: String
    var persistedUsername: String
    var usernameChangeCount: Int
    var traderType: TraderType?
}
