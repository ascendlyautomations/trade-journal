import Foundation

/// Web-parity username rules — mirrors `lib/profileUsername.ts`.
nonisolated enum ProfileUsernamePolicy {
    static let formatHint = "Only lowercase letters, numbers, and underscores allowed"

    private static let invalidCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_").inverted

    static func sanitizeForTyping(_ value: String) -> String {
        value.lowercased().unicodeScalars.filter { !invalidCharacters.contains($0) }.map(String.init).joined()
    }

    static func normalize(_ value: String) -> String {
        sanitizeForTyping(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func validateNotEmpty(_ value: String) -> String? {
        normalize(value).isEmpty ? "Please choose a username." : nil
    }

    static func isProfilesUsernameConflict(_ error: Error) -> Bool {
        let description = String(describing: error).lowercased()
        return description.contains("23505") && description.contains("username")
    }

    /// Native profile-shell fallback — not a user-chosen username.
    static func isGeneratedShellUsername(_ username: String?, profileID: ProfileID) -> Bool {
        guard let username else { return false }
        let normalized = normalize(username)
        guard normalized.hasPrefix("user_") else { return false }
        let expected = generatedShellUsername(for: profileID)
        return normalized == expected
    }

    static func generatedShellUsername(for profileID: ProfileID) -> String {
        let prefix = profileID.rawValue
            .replacingOccurrences(of: "-", with: "")
            .prefix(8)
        return "user_\(prefix)".lowercased()
    }

    /// Username shown in onboarding — blank when only the auto shell exists.
    static func onboardingPrefillUsername(current: String?, profileID: ProfileID) -> String {
        guard let current, !current.isEmpty else { return "" }
        if isGeneratedShellUsername(current, profileID: profileID) { return "" }
        return sanitizeForTyping(current)
    }
}
