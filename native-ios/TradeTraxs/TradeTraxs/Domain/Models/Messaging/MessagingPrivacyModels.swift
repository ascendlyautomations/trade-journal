import Foundation

/// Web/backend `profiles.dm_privacy` — authoritative DM audience values.
nonisolated enum DmPrivacy: String, Hashable, Codable, Sendable, CaseIterable {
    case everyone
    case following
    case followers
    case mutual

    var settingsTitle: String {
        switch self {
        case .everyone: return "Everyone"
        case .following: return "People I follow"
        case .followers: return "Followers"
        case .mutual: return "Mutual follows"
        }
    }

    var settingsSubtitle: String {
        switch self {
        case .everyone:
            return "Any trader can start a direct message with you."
        case .following:
            return "Only accounts you follow can message you."
        case .followers:
            return "Only accounts that follow you can message you."
        case .mutual:
            return "Only mutual follows can message you."
        }
    }

    static func parse(_ raw: String?) -> DmPrivacy {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return DmPrivacy(rawValue: trimmed) ?? .everyone
    }
}

nonisolated struct DmBlockStatus: Hashable, Sendable {
    var otherUserID: ProfileID
    var blockedByMe: Bool
    var blockedByOther: Bool

    var isMessagingBlocked: Bool {
        blockedByMe || blockedByOther
    }
}

nonisolated struct BlockedAccount: Hashable, Sendable, Identifiable {
    var id: ProfileID { profile.id }
    var profile: Profile
    var blockedAt: Date?
}

nonisolated struct MutedDirectMessagePeer: Hashable, Sendable, Identifiable {
    var id: ProfileID { profile.id }
    var profile: Profile
    var conversationID: ConversationID
}

// MARK: - Settings privacy list presentation

nonisolated enum MessagingPrivacyProfileFactory {
    static func profile(
        id profileID: ProfileID,
        username: String?,
        displayName name: String?,
        avatarURL: String?,
        createdAt: Date = .distantPast
    ) -> Profile {
        let trimmedUsername = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedUsername: String
        if trimmedUsername.isEmpty {
            resolvedUsername = ""
        } else {
            resolvedUsername = ProfileUsernamePolicy.resolvedPublicUsername(
                primary: trimmedUsername,
                profileID: profileID,
                fallback: nil
            )
        }

        let displayName: String
        if let rawName = name?.trimmingCharacters(in: .whitespacesAndNewlines), !rawName.isEmpty {
            displayName = rawName
        } else if !trimmedUsername.isEmpty {
            displayName = trimmedUsername
        } else {
            displayName = ""
        }

        return Profile(
            id: profileID,
            userID: UserID(profileID.rawValue),
            username: resolvedUsername,
            displayName: displayName,
            bio: nil,
            avatar: avatarURL.flatMap { url in
                let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : MediaReference(id: trimmed, kind: .image, altText: nil)
            },
            traderType: nil,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: createdAt
        )
    }
}

extension Profile {
    /// Primary line for Settings privacy rows — `@handle` when known.
    var settingsPrivacyUsernameLine: String {
        let handle = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !handle.isEmpty else { return "Blocked account" }
        return "@\(handle)"
    }

    /// Secondary line when a real display name exists and differs from the handle.
    var settingsPrivacyDisplayNameLine: String? {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let handle = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if !handle.isEmpty, name.compare(handle, options: .caseInsensitive) == .orderedSame {
            return nil
        }
        return name
    }
}
