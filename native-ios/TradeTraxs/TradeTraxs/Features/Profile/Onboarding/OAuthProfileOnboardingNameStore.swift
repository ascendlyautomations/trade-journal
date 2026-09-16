import Foundation

/// Transient OAuth display name for profile onboarding prefill (memory only).
@MainActor
enum OAuthProfileOnboardingNameStore {
    private static var pendingByUserID: [String: String] = [:]

    static func stage(fullName: String?, for userID: UserID) {
        guard let normalized = ProfileDisplayNamePolicy.normalized(fullName) else { return }
        pendingByUserID[userID.rawValue] = normalized
    }

    static func consume(for userID: UserID) -> String? {
        pendingByUserID.removeValue(forKey: userID.rawValue)
    }

    static func discard(for userID: UserID) {
        pendingByUserID.removeValue(forKey: userID.rawValue)
    }

    static func resetAll() {
        pendingByUserID.removeAll()
    }
}

enum ProfileOnboardingNamePrefill {
    /// Saved profile name → staged OAuth name → empty.
    static func editableName(snapshot: ProfileOnboardingSnapshot, userID: UserID) -> String {
        if let saved = ProfileDisplayNamePolicy.normalized(snapshot.displayName),
           !ProfileDisplayNamePolicy.isPlaceholder(saved)
        {
            OAuthProfileOnboardingNameStore.discard(for: userID)
            return saved
        }
        if let staged = OAuthProfileOnboardingNameStore.consume(for: userID) {
            return staged
        }
        return ""
    }
}
