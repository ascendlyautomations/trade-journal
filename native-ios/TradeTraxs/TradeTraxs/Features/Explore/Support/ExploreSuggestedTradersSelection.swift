import Foundation

/// Suggested-trader eligibility and presentation — home preview vs full directory.
enum ExploreSuggestedTradersSelection {
    /// Horizontal Explore rail — five discoverable traders with avatars.
    static let homePreviewCount = 5

    /// Discoverable traders (excludes viewer and followed). Avatars do not affect eligibility.
    static func discoverable(
        _ traders: [ExploreTraderSuggestion],
        viewerID: ProfileID?,
        followingIDs: Set<ProfileID>
    ) -> [ExploreTraderSuggestion] {
        traders.filter { trader in
            if let viewerID, trader.id == viewerID { return false }
            if followingIDs.contains(trader.id) { return false }
            return true
        }
    }

    /// Full directory ordering — avatar holders first, stable order within each group.
    static func discoverableAvatarFirst(
        _ traders: [ExploreTraderSuggestion],
        viewerID: ProfileID?,
        followingIDs: Set<ProfileID>,
        profile: (ExploreTraderSuggestion) -> Profile
    ) -> [ExploreTraderSuggestion] {
        let base = discoverable(traders, viewerID: viewerID, followingIDs: followingIDs)
        return ExploreTraderRanking.preservingOrderPreferringProfilePictures(base, profile: profile)
    }

    /// Home-rail candidates — discoverable and must have a profile picture.
    static func eligible(
        _ traders: [ExploreTraderSuggestion],
        viewerID: ProfileID?,
        followingIDs: Set<ProfileID>,
        profile: (ExploreTraderSuggestion) -> Profile
    ) -> [ExploreTraderSuggestion] {
        discoverable(traders, viewerID: viewerID, followingIDs: followingIDs).filter { trader in
            ExploreTraderRanking.hasValidProfilePicture(profile(trader))
        }
    }

    static func homePreview(
        _ traders: [ExploreTraderSuggestion],
        viewerID: ProfileID?,
        followingIDs: Set<ProfileID>,
        profile: (ExploreTraderSuggestion) -> Profile
    ) -> [ExploreTraderSuggestion] {
        Array(
            eligible(
                traders,
                viewerID: viewerID,
                followingIDs: followingIDs,
                profile: profile
            ).prefix(homePreviewCount)
        )
    }
}