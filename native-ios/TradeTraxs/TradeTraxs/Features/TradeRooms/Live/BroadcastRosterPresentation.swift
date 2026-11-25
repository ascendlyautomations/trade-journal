import Foundation

/// Member list labels and identity filtering for broadcast rosters.
enum BroadcastRosterPresentation {
  static func shouldListInRoster(
        identity: String,
        programPublisherIdentity: String?
    ) -> Bool {
        guard ProfileIDQueryPolicy.isQueryable(ProfileID(identity)) else { return false }
        return !BroadcastObsProgramVideo.isIngressPublisherIdentity(
            identity,
            programPublisherIdentity: programPublisherIdentity
        )
    }

    /// Primary row label — prefer profile username, then display name; never raw LiveKit identity.
    static func memberRowLabel(
        profile: Profile?,
        liveKitFallbackName: String,
        userId: String
    ) -> String {
        if let profile {
            let username = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
            if !username.isEmpty {
                return username.hasPrefix("@") ? String(username.dropFirst()) : username
            }
            let name = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        if ProfileIDQueryPolicy.isQueryable(ProfileID(userId)) {
            return "Loading…"
        }
        let fallback = liveKitFallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
        if fallback.isEmpty || fallback == userId || looksLikeOpaqueIdentity(fallback) {
            return "Member"
        }
        return fallback
    }

    static func moderationDisplayName(
        profile: Profile?,
        participant: BroadcastRosterParticipant
    ) -> String {
        memberRowLabel(
            profile: profile,
            liveKitFallbackName: participant.displayName,
            userId: participant.identity
        )
    }

    private static func looksLikeOpaqueIdentity(_ value: String) -> Bool {
        if value.hasPrefix(BroadcastObsProgramVideo.ingressIdentityPrefix) { return true }
        if value.contains("…") || value.contains("...") { return true }
        let lower = value.lowercased()
        if lower.count <= 8, lower.allSatisfy({ $0.isHexDigit || $0 == "-" }) { return true }
        if UUID(uuidString: value) != nil { return true }
        return false
    }
}