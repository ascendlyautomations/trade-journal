import Foundation

/// Explore Mode capability surface — unauthenticated guest reads + local demo journal.
@MainActor
enum ExploreModeSupport {
    static var isActive: Bool {
        AppLaunchController.shared.isDemoExperienceActive
    }

    /// Demo Feed uses bundled fixtures for Global and Following. Guest RPC scope lock stays off.
    static var usesLiveCommunityFeed: Bool { false }

    /// Cache key identity for guest Feed — not a Supabase user id.
    static let guestFeedViewerID = ProfileID("explore.guest.feed")

    /// Bundled Explore has no session, so it skips viewer services.
    /// A guest-issued session keeps those services so Feed, Messages, and Rooms
    /// load for the real showcase account.
    static var skipsAuthenticatedViewerServices: Bool {
        isActive && DemoExperienceSupport.skipsAuthenticatedViewerServices
    }

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
