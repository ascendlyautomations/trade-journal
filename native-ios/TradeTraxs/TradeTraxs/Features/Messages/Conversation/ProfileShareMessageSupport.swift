import Foundation

/// Trader profile share DM / Trade Room payload.
nonisolated enum ProfileShareMessageSupport {
    static let messageType = "profile_share"

    struct Payload: Equatable, Sendable {
        var profileID: String
        var username: String?
        var displayName: String?
        var avatarURL: String?
    }

    static func encode(profile: Profile) -> String {
        encode(
            profileID: profile.id,
            username: profile.username,
            displayName: profile.displayName,
            avatarURL: profile.avatar?.id
        )
    }

    static func encode(
        profileID: ProfileID,
        username: String?,
        displayName: String?,
        avatarURL: String?
    ) -> String {
        var payload: [String: Any] = ["shared_profile_id": profileID.rawValue]
        if let trimmedUsername = username?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmedUsername.isEmpty
        {
            payload["profile_username"] = trimmedUsername
        }
        if let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmedName.isEmpty
        {
            payload["profile_display_name"] = trimmedName
        }
        if let trimmedAvatar = avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmedAvatar.isEmpty
        {
            payload["profile_avatar_url"] = trimmedAvatar
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return json
    }

    static func decode(from content: String?) -> Payload? {
        guard let raw = content?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        guard let profileID = json["shared_profile_id"] as? String else { return nil }
        let trimmedID = profileID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return nil }

        let username = (json["profile_username"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (json["profile_display_name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let avatarURL = (json["profile_avatar_url"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Payload(
            profileID: trimmedID,
            username: username?.isEmpty == false ? username : nil,
            displayName: displayName?.isEmpty == false ? displayName : nil,
            avatarURL: avatarURL?.isEmpty == false ? avatarURL : nil
        )
    }

    static func isProfileShare(type: String?, content: String?) -> Bool {
        if type?.lowercased() == messageType { return true }
        let normalizedType = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedType == nil || normalizedType == "text" {
            return decode(from: content) != nil
        }
        return false
    }

    static func previewText(from content: String?, emptyFallback: String = "Shared a profile") -> String {
        guard let payload = decode(from: content) else {
            return emptyFallback
        }
        return cardTitle(payload: payload)
    }

    static func cardTitle(payload: Payload) -> String {
        if let username = payload.username, !username.isEmpty {
            return "@\(username)'s profile"
        }
        if let name = payload.displayName, !name.isEmpty {
            return "\(name)'s profile"
        }
        return "Shared a profile"
    }
}

enum ProfileShareNavigation {
    @MainActor
    static func open(
        payload: ProfileShareMessageSupport.Payload,
        cache: DetailPresentationCache,
        coordinator: NavigationCoordinator?
    ) {
        let profileID = ProfileID(payload.profileID)
        if cache.profile(id: profileID) == nil,
           let username = payload.username, !username.isEmpty
        {
            cache.seed(
                Profile(
                    id: profileID,
                    userID: UserID(profileID.rawValue),
                    username: username,
                    displayName: payload.displayName ?? username,
                    bio: nil,
                    avatar: payload.avatarURL.map {
                        MediaReference(id: $0, kind: .image, altText: nil)
                    },
                    traderType: nil,
                    tradingStyle: nil,
                    primaryMarket: nil,
                    startedTradingAt: nil,
                    isPrivate: false,
                    isCreator: false,
                    createdAt: .now
                )
            )
        }
        ExperienceHaptics.play(.selection)
        coordinator?.pushOtherProfile(profileID)
    }
}
