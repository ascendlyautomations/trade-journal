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
    static func profileNeedsUsername(_ username: String?, profileID: ProfileID) -> Bool {
        guard let username else { return true }
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        return ProfileUsernamePolicy.isGeneratedShellUsername(trimmed, profileID: profileID)
    }

    static func profileFieldMissing(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func profileNeedsDisplayName(_ name: String?) -> Bool {
        profileFieldMissing(name) || ProfileDisplayNamePolicy.isPlaceholder(name)
    }

    /// True when the user must complete global onboarding before app access.
    static func profileNeedsOnboarding(_ snapshot: ProfileOnboardingSnapshot) -> Bool {
        if snapshot.onboardingCompleted { return false }
        return profileNeedsDisplayName(snapshot.displayName)
            || profileNeedsUsername(snapshot.username, profileID: snapshot.profileID)
            || profileFieldMissing(snapshot.traderType)
            || profileFieldMissing(snapshot.tradingStyle)
            || profileFieldMissing(snapshot.startedTrading)
            || !snapshot.onboardingCompleted
    }
}

nonisolated extension ProfileOnboardingSnapshot {
    static func from(
        session: SessionProfileV1,
        viewer: ViewerCardV1,
        viewerID: String
    ) -> ProfileOnboardingSnapshot {
        ProfileOnboardingSnapshot(
            profileID: ProfileID(viewerID),
            username: session.username,
            displayName: resolvedDisplayName(viewer: viewer, session: session),
            onboardingCompleted: session.onboarding_completed == true,
            traderType: session.trader_type,
            tradingStyle: session.trading_style,
            startedTrading: session.started_trading,
            bio: session.bio,
            avatarURL: resolvedAvatarURL(viewer: viewer, session: session)
        )
    }

    private static func resolvedDisplayName(
        viewer: ViewerCardV1,
        session: SessionProfileV1
    ) -> String? {
        _ = session
        guard let normalized = ProfileDisplayNamePolicy.normalized(viewer.display_name),
              !ProfileDisplayNamePolicy.isPlaceholder(normalized)
        else {
            return nil
        }
        return normalized
    }

    private static func resolvedAvatarURL(
        viewer: ViewerCardV1,
        session: SessionProfileV1
    ) -> String? {
        for raw in [session.avatar_url, viewer.avatar_url] {
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
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
