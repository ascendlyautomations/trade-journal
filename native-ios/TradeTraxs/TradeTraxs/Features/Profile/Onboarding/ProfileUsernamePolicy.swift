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
        if let network = error as? NetworkError,
           case .validation(_, let message) = network {
            return postgrestUsernameConflict(in: message)
        }
        if let network = error as? NetworkError,
           case .server(_, let message) = network {
            return postgrestUsernameConflict(in: message)
        }
        let description = String(describing: error).lowercased()
        return postgrestUsernameConflict(in: description)
    }

    private static func postgrestUsernameConflict(in raw: String?) -> Bool {
        guard let raw else { return false }
        let lower = raw.lowercased()
        return lower.contains("23505") && lower.contains("username")
    }

    /// True when the normalized value is already on this profile (including shell username).
    static func isSameAsCurrentProfileUsername(
        _ normalized: String,
        currentUsername: String?,
        profileID: ProfileID
    ) -> Bool {
        guard let currentUsername else { return false }
        let currentNormalized = normalize(currentUsername)
        if currentNormalized.isEmpty { return false }
        if normalized == currentNormalized { return true }
        return isGeneratedShellUsername(currentUsername, profileID: profileID)
            && normalized == normalize(currentUsername)
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
