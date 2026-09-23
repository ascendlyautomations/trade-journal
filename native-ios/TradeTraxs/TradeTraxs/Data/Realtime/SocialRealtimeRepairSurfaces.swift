import Foundation

/// Weak registration of UI surfaces eligible for bounded reconnect repair (no global store).
@MainActor
final class SocialRealtimeRepairSurfaces {
    static let shared = SocialRealtimeRepairSurfaces()

    weak var feedViewModel: FeedScreenViewModel?
    weak var profileViewModel: ProfileScreenViewModel?
    var repairOpenConversation: (() async -> Void)?
    var repairOpenRoom: (() async -> Void)?
    var profileRepairGeneration: UInt64 = 0

    private init() {}

    func clearSession() {
        feedViewModel = nil
        profileViewModel = nil
        repairOpenConversation = nil
        repairOpenRoom = nil
        profileRepairGeneration = 0
    }

    func bumpProfileRepairGeneration() {
        profileRepairGeneration &+= 1
    }
}
