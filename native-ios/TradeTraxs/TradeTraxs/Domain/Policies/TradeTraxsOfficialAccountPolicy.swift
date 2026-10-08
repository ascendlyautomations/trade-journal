import Foundation

/// Official @tradetraxs account — badge eligibility is profile-ID based (not username).
nonisolated enum TradeTraxsOfficialAccountPolicy {
    /// Production Supabase `profiles.id` for @tradetraxs.
    static let profileID = ProfileID("de0ad507-4cb4-4c09-a5eb-46536567e2c3")

    static func isOfficialTradeTraxsAccount(profileID: ProfileID) -> Bool {
        if profileID == Self.profileID { return true }
        if ProfileIDQueryPolicy.isOfficialRoomSystemOwner(profileID) { return true }
        return false
    }

    /// Hexagon badge beside identity — official account or existing creator verification.
    static func showsTradeTraxsIdentityBadge(profileID: ProfileID, isCreator: Bool) -> Bool {
        isCreator || isOfficialTradeTraxsAccount(profileID: profileID)
    }

    static func badgeAccessibilityLabel(profileID: ProfileID, isCreator: Bool) -> String {
        if isOfficialTradeTraxsAccount(profileID: profileID) {
            return "Official TradeTraxs account"
        }
        return "Verified"
    }

    static func showsTradeTraxsIdentityBadge(owner: Profile?, ownerProfileID: ProfileID) -> Bool {
        if let owner {
            return showsTradeTraxsIdentityBadge(profileID: owner.id, isCreator: owner.isCreator)
        }
        return isOfficialTradeTraxsAccount(profileID: ownerProfileID)
    }
}

extension Profile {
    nonisolated var showsTradeTraxsIdentityBadge: Bool {
        TradeTraxsOfficialAccountPolicy.showsTradeTraxsIdentityBadge(
            profileID: id,
            isCreator: isCreator
        )
    }
}
