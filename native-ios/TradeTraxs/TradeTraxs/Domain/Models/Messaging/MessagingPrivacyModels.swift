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
