import Foundation

/// Logged-out Explore Mode — local demo journal and bundled community fixtures.
///
/// **Journal:** Dashboard, trades, calendar, and analytics for ``profileID`` use ``DemoCanonicalDataset`` only.
/// **Community:** Feed, Explore, and Trade Rooms use bundled fixtures for this identity.
/// Live guest RPCs stay available for non-demo callers; Demo Mode does not require them.
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

    /// Bundled Feed/Explore/Room fixtures for demo and `dev.*` identities.
    /// Demo Mode always uses these, including while the explore inbox flag is on.
    static func usesLocalBundledSocialData(_ id: ProfileID) -> Bool {
        usesLocalBundledData(id)
    }

    /// Explore Mode Messages tab — local demo DMs only (no ``rpc_v2_messaging_bootstrap``).
    static func usesExploreDemoInbox(_ id: ProfileID) -> Bool {
        exploreLiveCommunityReadsActive && id == profileID
    }

    /// Skip Activity, notifications, and other authenticated viewer services (no Supabase user session).
    static var skipsAuthenticatedViewerServices: Bool { exploreLiveCommunityReadsActive }
}
