import Foundation

nonisolated struct ProfileOnboardingSubmission: Sendable, Equatable {
    var profileID: ProfileID
    var username: String
    var displayName: String?
    var bio: String?
    var tradingStyle: String
    var traderType: TraderType
    var startedTrading: String
    var avatarURL: String?
    var primaryMarket: String?
}
