import Foundation

/// Messaging / inbox primary identity line — never surfaces auth placeholders or profile-shell usernames.
nonisolated enum ProfileDisplayNameResolver {
    static let newUserFallback = "New User"

    static func profileDisplayName(for profile: Profile) -> String {
        profileDisplayName(
            displayName: profile.displayName,
            username: profile.username,
            profileID: profile.id
        )
    }

    static func profileDisplayName(
        displayName: String?,
        username: String?,
        profileID: ProfileID?
    ) -> String {
        if let name = resolvedPublicDisplayName(displayName, profileID: profileID) {
            return name
        }
        if let handle = resolvedChosenUsername(username, profileID: profileID) {
            return handle
        }
        return newUserFallback
    }

    /// Secondary `@username` line on DM rows — hidden for shell / UUID-like handles.
    static func messagingUsernameSubtitle(
        username: String?,
        profileID: ProfileID?
    ) -> String? {
        guard let handle = resolvedChosenUsername(username, profileID: profileID) else { return nil }
        return "@\(handle)"
    }

    private static func resolvedPublicDisplayName(
        _ raw: String?,
        profileID: ProfileID?
    ) -> String? {
        guard !ProfileDisplayNamePolicy.isPlaceholder(raw),
              let trimmed = ProfileDisplayNamePolicy.normalized(raw)
        else {
            return nil
        }
        guard let sanitized = ProfileIdentitySanitizer.sanitizedPublicField(trimmed) else { return nil }
        if let profileID,
           ProfileUsernamePolicy.isGeneratedShellUsername(sanitized, profileID: profileID)
        {
            return nil
        }
        return sanitized
    }

    private static func resolvedChosenUsername(
        _ raw: String?,
        profileID: ProfileID?
    ) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let profileID,
           ProfileUsernamePolicy.isGeneratedShellUsername(trimmed, profileID: profileID)
        {
            return nil
        }
        return ProfileIdentitySanitizer.sanitizedPublicField(trimmed)
    }
}
