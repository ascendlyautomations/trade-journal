import Foundation

/// Transient display names for profile onboarding prefill (memory only).
@MainActor
enum OAuthProfileOnboardingNameStore {
    private static var manualSignupByUserID: [String: String] = [:]
    private static var providerByUserID: [String: String] = [:]
    /// Email sign-up awaiting confirmation — promoted to ``manualSignupByUserID`` on first session.
    private static var manualSignupByEmail: [String: String] = [:]

    /// Create Account form (email/password) — beats provider names.
    static func stageManualSignup(fullName: String?, for userID: UserID) {
        guard let normalized = ProfileDisplayNamePolicy.normalized(fullName) else { return }
        manualSignupByUserID[userID.rawValue] = normalized
    }

    /// Create Account before email confirmation (no session yet).
    static func stageManualSignupPendingEmail(fullName: String?, email: String) {
        guard let normalized = ProfileDisplayNamePolicy.normalized(fullName),
              let key = normalizedEmailKey(email)
        else { return }
        manualSignupByEmail[key] = normalized
    }

    /// Apple / Google (or other) — never overwrites manual signup name.
    static func stageProvider(fullName: String?, for userID: UserID) {
        guard let normalized = ProfileDisplayNamePolicy.normalized(fullName) else { return }
        guard manualSignupByUserID[userID.rawValue] == nil else { return }
        providerByUserID[userID.rawValue] = normalized
    }

    static func bindEmailPendingToUserIfNeeded(email: String?, userID: UserID) {
        guard manualSignupByUserID[userID.rawValue] == nil,
              let key = email.flatMap(normalizedEmailKey(_:)),
              let pending = manualSignupByEmail.removeValue(forKey: key)
        else { return }
        manualSignupByUserID[userID.rawValue] = pending
    }

    static func peek(for userID: UserID) -> String? {
        manualSignupByUserID[userID.rawValue] ?? providerByUserID[userID.rawValue]
    }

    static func discard(for userID: UserID) {
        manualSignupByUserID.removeValue(forKey: userID.rawValue)
        providerByUserID.removeValue(forKey: userID.rawValue)
    }

    static func resetAll() {
        manualSignupByUserID.removeAll()
        providerByUserID.removeAll()
        manualSignupByEmail.removeAll()
    }

    private static func normalizedEmailKey(_ email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum ProfileOnboardingNamePrefill {
    /// 1) Saved profile name → 2) manual Create Account → 3) provider → empty.
    static func editableName(snapshot: ProfileOnboardingSnapshot, userID: UserID) -> String {
        if let saved = ProfileDisplayNamePolicy.normalized(snapshot.displayName),
           !ProfileDisplayNamePolicy.isPlaceholder(saved)
        {
            OAuthProfileOnboardingNameStore.discard(for: userID)
            return saved
        }
        if let staged = OAuthProfileOnboardingNameStore.peek(for: userID) {
            return staged
        }
        return ""
    }
}
