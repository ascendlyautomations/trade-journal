import Foundation
import Observation

/// Session-scoped optimistic overlays for the **owner** Profile.
///
/// ``ProfileScreenViewModel.state`` remains the UI source of truth. This store only:
/// 1. Holds created models until the owner Profile screen can absorb them
/// 2. Re-merges those models into bootstrap snapshots (no network refresh)
///
/// Create flows call ``notePostCreated`` / ``noteReelCreated`` / ``noteAchievementCreated``;
/// the owner Profile screen registers and applies immediately when present.
@Observable
@MainActor
final class OwnerProfileOptimisticStore {
    static let shared = OwnerProfileOptimisticStore()

    private(set) var revision: Int = 0
    private(set) var posts: [Post] = []
    private(set) var reels: [Reel] = []
    private(set) var achievements: [Achievement] = []

    /// Weak so logout / tab teardown does not retain a dead screen.
    private weak var ownerScreen: ProfileScreenViewModel?

    private init() {}

    func registerOwnerScreen(_ screen: ProfileScreenViewModel) {
        ownerScreen = screen
        screen.absorbOwnerOptimisticOverlays()
    }

    func unregisterOwnerScreen(_ screen: ProfileScreenViewModel) {
        if ownerScreen === screen {
            ownerScreen = nil
        }
    }

    func notePostCreated(_ post: Post) {
        posts = Self.upserting(post, into: posts)
        ownerScreen?.applyOptimisticPost(post)
        ContentMutationStore.shared.notePostCreated(post)
        revision += 1
    }

    func noteReelCreated(_ reel: Reel) {
        guard Self.isListedOnOwnerProfile(reel) else {
            // Still notify Feed / other observers; Profile Clips skips private trade-linked.
            ContentMutationStore.shared.noteReelCreated(reel)
            return
        }
        reels = Self.upserting(reel, into: reels)
        ownerScreen?.applyOptimisticReel(reel)
        ContentMutationStore.shared.noteReelCreated(reel)
        revision += 1
    }

    func noteAchievementCreated(_ achievement: Achievement) {
        achievements = Self.upserting(achievement, into: achievements)
        ownerScreen?.applyOptimisticAchievement(achievement)
        ContentMutationStore.shared.noteAchievementCreated(achievement.id)
        revision += 1
    }

    func notePostDeleted(id: PostID) {
        posts.removeAll { $0.id == id }
        ownerScreen?.applyOptimisticPostRemoval(id: id)
        revision += 1
    }

    func noteReelDeleted(id: ReelID) {
        reels.removeAll { $0.id == id }
        ownerScreen?.applyOptimisticReelRemoval(id: id)
        revision += 1
    }

    /// Merge overlays into a bootstrap / refresh snapshot (dedupe by id, overlay wins).
    func merging(into state: ProfileState) -> ProfileState {
        guard state.isOwner || ownerMatches(state.profileID) else { return state }
        var next = state
        next.posts = Self.merging(overlay: posts, into: next.posts)
        next.clips = Self.merging(overlay: reels, into: next.clips)
        next.achievements = Self.merging(overlay: achievements, into: next.achievements)
        return next
    }

    func invalidate() {
        posts = []
        reels = []
        achievements = []
        ownerScreen = nil
        revision = 0
    }

    // MARK: - Merge helpers (testable)

    /// Standalone clips always list; trade-linked only when public (web `isReelListedOnProfile`).
    static func isListedOnOwnerProfile(_ reel: Reel) -> Bool {
        guard reel.linkedTradeID != nil else { return true }
        return reel.visibility == .public
    }

    static func upserting<T: Identifiable>(_ item: T, into items: [T]) -> [T] where T.ID: Hashable {
        var next = items.filter { $0.id != item.id }
        next.insert(item, at: 0)
        return next
    }

    /// Overlay items appear first; base fills the rest without duplicates.
    static func merging<T: Identifiable>(overlay: [T], into base: [T]) -> [T] where T.ID: Hashable {
        guard !overlay.isEmpty else { return base }
        var seen = Set(overlay.map(\.id))
        var result = overlay
        for item in base where !seen.contains(item.id) {
            seen.insert(item.id)
            result.append(item)
        }
        return result
    }

    private func ownerMatches(_ profileID: ProfileID?) -> Bool {
        guard let profileID else { return false }
        return posts.contains { $0.authorProfileID == profileID }
            || reels.contains { $0.authorProfileID == profileID }
            || achievements.contains { $0.ownerProfileID == profileID }
    }
}
