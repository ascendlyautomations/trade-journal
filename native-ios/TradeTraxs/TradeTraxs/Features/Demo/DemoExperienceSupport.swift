import Foundation

/// Logged-out Explore Mode — local demo journal + guest public community repositories.
///
/// **Journal:** Dashboard, trades, calendar, and analytics for ``profileID`` use ``DemoCanonicalDataset`` only.
/// **Community:** Feed / Explore / public Trade Rooms use anon guest RPCs (see ``ExploreGuestRepositories``).
///
/// ``profileID`` is a local fixture identifier only — not a Supabase user.
nonisolated enum DemoExperienceSupport {
    static let profileID = ProfileID("demo.explore.trader")

    nonisolated(unsafe) private static var exploreLiveCommunityReadsActive = false

    static func setExploreLiveCommunityReadsActive(_ active: Bool) {
        exploreLiveCommunityReadsActive = active
    }

    /// Profiles whose trading/social data ships in the app bundle (debug `dev.*` + production demo).
    static func usesLocalBundledData(_ id: ProfileID) -> Bool {
        id == profileID || id.rawValue.hasPrefix("dev.")
    }

    /// Bundled Feed/Explore/Room fixtures — off while Explore uses live guest community reads.
    static func usesLocalBundledSocialData(_ id: ProfileID) -> Bool {
        usesLocalBundledData(id) && !exploreLiveCommunityReadsActive
    }

    /// Explore Mode Messages tab — local demo DMs only (no ``rpc_v2_messaging_bootstrap``).
    static func usesExploreDemoInbox(_ id: ProfileID) -> Bool {
        exploreLiveCommunityReadsActive && id == profileID
    }

    /// Skip Activity, notifications, and other authenticated viewer services (no Supabase user session).
    static var skipsAuthenticatedViewerServices: Bool { exploreLiveCommunityReadsActive }
}
