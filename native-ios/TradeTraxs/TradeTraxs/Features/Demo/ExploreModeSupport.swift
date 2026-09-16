import Foundation

/// Explore Mode capability surface — unauthenticated guest reads + local demo journal.
@MainActor
enum ExploreModeSupport {
    static var isActive: Bool {
        AppLaunchController.shared.isDemoExperienceActive
    }

    /// Personal journal tabs use bundled demo data; community uses guest public repositories.
    static var usesLiveCommunityFeed: Bool { isActive }

    /// Cache key identity for guest Feed — not a Supabase user id.
    static let guestFeedViewerID = ProfileID("explore.guest.feed")

    /// Skip authenticated viewer services (blocks, messaging bootstrap, follow sync, Realtime).
    static var skipsAuthenticatedViewerServices: Bool { isActive }

    static var canWriteContent: Bool { !isActive }
    static var canInteractSocially: Bool { !isActive }
    static var canMessage: Bool { !isActive }
    static var canJoinRooms: Bool { !isActive }
    static var canConnectBroker: Bool { !isActive }
    static var canManageAccount: Bool { !isActive }
    static var canPurchase: Bool { !isActive }
    static var canViewPublicCommunity: Bool { true }

    /// Guest Feed is global discovery only (server-enforced for anon JWT).
    static var feedScope: FeedScope { .global }
}
