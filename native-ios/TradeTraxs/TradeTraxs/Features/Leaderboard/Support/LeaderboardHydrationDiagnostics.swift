import Foundation
import OSLog

#if DEBUG
/// Temporary leaderboard hydration counters — never log user IDs or avatar URLs.
nonisolated enum LeaderboardHydrationDiagnostics {
    static func log(
        filter: String,
        rows: [LeaderboardRow],
        profiles: [ProfileID: Profile]
    ) {
        let visibleIDs = Set(rows.map(\.profileID))
        let resolved = visibleIDs.filter { id in
            guard let profile = profiles[id] else { return false }
            return LeaderboardTradeIdentity.isUsableLeaderboardProfile(profile)
        }.count
        let avatars = visibleIDs.filter { profiles[$0]?.avatar != nil }.count
        let missing = visibleIDs.count - resolved

        AppLog.networking.debug(
            """
            leaderboard.hydration filter=\(filter, privacy: .public) \
            visibleUserCount=\(visibleIDs.count, privacy: .public) \
            resolvedProfileCount=\(resolved, privacy: .public) \
            avatarAvailableCount=\(avatars, privacy: .public) \
            missingProfileCount=\(missing, privacy: .public)
            """
        )
    }
}
#endif
