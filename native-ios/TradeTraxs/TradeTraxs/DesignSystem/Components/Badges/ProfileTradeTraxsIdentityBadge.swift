import SwiftUI

/// Inline TradeTraxs hexagon badge for profile identity rows (official account + creators).
struct ProfileTradeTraxsIdentityBadge: View {
    let profileID: ProfileID
    var isCreator: Bool = false
    var size: TradeTraxsVerifiedBadge.Size = .compact

    init(profile: Profile, size: TradeTraxsVerifiedBadge.Size = .compact) {
        profileID = profile.id
        isCreator = profile.isCreator
        self.size = size
    }

    init(
        profileID: ProfileID,
        isCreator: Bool = false,
        size: TradeTraxsVerifiedBadge.Size = .compact
    ) {
        self.profileID = profileID
        self.isCreator = isCreator
        self.size = size
    }

    var body: some View {
        if TradeTraxsOfficialAccountPolicy.showsTradeTraxsIdentityBadge(
            profileID: profileID,
            isCreator: isCreator
        ) {
            TradeTraxsVerifiedBadge(
                size: size,
                accessibilityLabel: TradeTraxsOfficialAccountPolicy.badgeAccessibilityLabel(
                    profileID: profileID,
                    isCreator: isCreator
                )
            )
        }
    }
}
