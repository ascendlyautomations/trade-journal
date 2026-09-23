import Foundation

/// Cache-validation token for Profile analytics GRDB rows (viewer + subject + visibility gate).
nonisolated struct ProfileAnalyticsVisibilityIdentity: Equatable, Sendable {
    var token: String

    static func locked(subjectProfileID: ProfileID) -> ProfileAnalyticsVisibilityIdentity {
        ProfileAnalyticsVisibilityIdentity(
            token: "locked|\(normalized(subjectProfileID))"
        )
    }

    static func from(snapshot: ProfileState, subjectProfileID: ProfileID) -> ProfileAnalyticsVisibilityIdentity {
        if !snapshot.canViewTrades, !snapshot.isOwner {
            return locked(subjectProfileID: subjectProfileID)
        }
        let isPrivate = snapshot.profile?.isPrivate == true
        let parts = [
            normalized(subjectProfileID),
            snapshot.isOwner ? "owner" : "viewer",
            snapshot.canViewTrades ? "canView" : "noView",
            snapshot.isFollowing ? "following" : "notFollowing",
            isPrivate ? "private" : "public",
        ]
        return ProfileAnalyticsVisibilityIdentity(token: parts.joined(separator: "|"))
    }

    static func fromCanView(
        canViewStatistics: Bool,
        subjectProfileID: ProfileID
    ) -> ProfileAnalyticsVisibilityIdentity {
        if canViewStatistics {
            return ProfileAnalyticsVisibilityIdentity(
                token: "canView|\(normalized(subjectProfileID))"
            )
        }
        return locked(subjectProfileID: subjectProfileID)
    }

    private static func normalized(_ profileID: ProfileID) -> String {
        profileID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
