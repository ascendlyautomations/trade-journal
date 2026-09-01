import Foundation

/// Identity embedded on leaderboard trade rows when the API supplies profile fields.
nonisolated struct LeaderboardTraderIdentity: Sendable, Equatable {
    var displayName: String?
    var username: String?
    var avatarURL: String?

    var hasResolvableIdentity: Bool {
        ProfileIdentitySanitizer.sanitizedPublicField(displayName) != nil
            || ProfileIdentitySanitizer.sanitizedPublicField(username) != nil
            || sanitizedAvatarURL != nil
    }

    private var sanitizedAvatarURL: String? {
        guard let avatarURL else { return nil }
        let trimmed = avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func makeProfile(profileID: ProfileID) -> Profile {
        let display = ProfileIdentitySanitizer.leaderboardDisplayName(
            name: displayName,
            username: username
        )
        let handle = ProfileIdentitySanitizer.leaderboardUsername(username) ?? ""
        let avatar = sanitizedAvatarURL.map {
            MediaReference(id: $0, kind: .image, altText: nil)
        }
        return Profile(
            id: profileID,
            userID: UserID(profileID.rawValue),
            username: handle,
            displayName: display,
            bio: nil,
            avatar: avatar,
            traderType: nil,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: .now
        )
    }
}

nonisolated enum LeaderboardTradeIdentity {
    /// JSON keys on `GET /api/leaderboard/trades` today: `user_id`, `pnl`, `rr`, `created_at`, `account_type`, `mode`.
    /// Optional forward-compatible keys: `username`, `name`, `avatar_url`.
    static func profiles(from trades: [LeaderboardTradeRow]) -> [ProfileID: Profile] {
        var identities: [ProfileID: LeaderboardTraderIdentity] = [:]
        for trade in trades {
            guard trade.embeddedIdentity.hasResolvableIdentity else { continue }
            let profileID = ProfileID(trade.userID)
            if identities[profileID] == nil {
                identities[profileID] = trade.embeddedIdentity
            }
        }
        return Dictionary(uniqueKeysWithValues: identities.map { id, identity in
            (id, identity.makeProfile(profileID: id))
        })
    }

    /// Reject DetailPresentationCache rows that only contain UUID placeholders.
    static func isUsableLeaderboardProfile(_ profile: Profile) -> Bool {
        ProfileIdentitySanitizer.sanitizedPublicField(profile.displayName) != nil
            || ProfileIdentitySanitizer.sanitizedPublicField(profile.username) != nil
            || profile.avatar != nil
    }

    /// Cache is complete only when identity is usable and avatar is present.
    /// Username-only cache hits must still batch-fetch so avatars hydrate.
    static func isLeaderboardCacheComplete(_ profile: Profile) -> Bool {
        isUsableLeaderboardProfile(profile) && profile.avatar != nil
    }

    static func mergeLeaderboardProfile(existing: Profile?, fetched: Profile) -> Profile {
        guard let existing else { return fetched }
        var merged = existing.mergingCachedPresentation(with: fetched)
        if ProfileIdentitySanitizer.sanitizedPublicField(merged.displayName) == nil,
           ProfileIdentitySanitizer.sanitizedPublicField(fetched.displayName) != nil {
            merged.displayName = fetched.displayName
        }
        if ProfileIdentitySanitizer.sanitizedPublicField(merged.username) == nil,
           ProfileIdentitySanitizer.sanitizedPublicField(fetched.username) != nil {
            merged.username = fetched.username
        }
        return merged
    }
}
