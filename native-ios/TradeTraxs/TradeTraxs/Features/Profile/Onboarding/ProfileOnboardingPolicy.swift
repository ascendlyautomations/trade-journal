import Foundation

/// Web-parity gate fields — mirrors ``profileNeedsOnboarding`` in `lib/profileOnboardingGate.ts`.
nonisolated struct ProfileOnboardingSnapshot: Sendable, Equatable {
    var profileID: ProfileID
    var username: String?
    var displayName: String?
    var onboardingCompleted: Bool
    var traderType: String?
    var tradingStyle: String?
    var startedTrading: String?
    var bio: String?
    var avatarURL: String?

    init(
        profileID: ProfileID,
        username: String? = nil,
        displayName: String? = nil,
        onboardingCompleted: Bool = false,
        traderType: String? = nil,
        tradingStyle: String? = nil,
        startedTrading: String? = nil,
        bio: String? = nil,
        avatarURL: String? = nil
    ) {
        self.profileID = profileID
        self.username = username
        self.displayName = displayName
        self.onboardingCompleted = onboardingCompleted
        self.traderType = traderType
        self.tradingStyle = tradingStyle
        self.startedTrading = startedTrading
        self.bio = bio
        self.avatarURL = avatarURL
    }
}

nonisolated enum ProfileOnboardingPolicy {
    static func profileNeedsUsername(_ username: String?) -> Bool {
        guard let username else { return true }
        return username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func profileFieldMissing(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True when the user must complete global onboarding before app access.
    static func profileNeedsOnboarding(_ snapshot: ProfileOnboardingSnapshot) -> Bool {
        if snapshot.onboardingCompleted { return false }
        return profileNeedsUsername(snapshot.username)
            || profileFieldMissing(snapshot.traderType)
            || profileFieldMissing(snapshot.tradingStyle)
            || profileFieldMissing(snapshot.startedTrading)
            || !snapshot.onboardingCompleted
    }
}

nonisolated extension ProfileOnboardingSnapshot {
    static func from(session: SessionProfileV1, viewerID: String) -> ProfileOnboardingSnapshot {
        ProfileOnboardingSnapshot(
            profileID: ProfileID(viewerID),
            username: session.username,
            displayName: nil,
            onboardingCompleted: session.onboarding_completed == true,
            traderType: session.trader_type,
            tradingStyle: session.trading_style,
            startedTrading: session.started_trading,
            bio: session.bio,
            avatarURL: nil
        )
    }

    static func from(dto: ProfileDTO.OnboardingFields, profileID: ProfileID) -> ProfileOnboardingSnapshot {
        ProfileOnboardingSnapshot(
            profileID: profileID,
            username: dto.username,
            displayName: dto.name,
            onboardingCompleted: dto.onboarding_completed == true,
            traderType: dto.trader_type,
            tradingStyle: dto.trading_style,
            startedTrading: dto.started_trading,
            bio: dto.bio,
            avatarURL: dto.avatar_url
        )
    }
}
