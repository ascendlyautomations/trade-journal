import Foundation
import Observation

/// Broadcasts Post / Achievement / Clip mutations for Feed and non-owner surfaces.
///
/// Owner Profile UI must absorb creates via ``OwnerProfileOptimisticStore`` —
/// do not treat this store as Profile list state.
@Observable
@MainActor
final class ContentMutationStore {
    static let shared = ContentMutationStore()

    enum Kind: Equatable {
        case post(Post)
        case achievement(AchievementID)
        case reel(Reel)
        case reelLinked(ReelID)
        case story(Story)
        case storyDeleted(StoryID)
    }

    private(set) var revision: Int = 0
    private(set) var latest: Kind?
    private(set) var latestPostID: PostID?
    private(set) var latestAchievementID: AchievementID?
    private(set) var latestReelID: ReelID?
    private(set) var latestStoryID: StoryID?
    private(set) var latestDeletedStoryID: StoryID?

    private init() {}

    func notePostCreated(_ post: Post) {
        latest = .post(post)
        latestPostID = post.id
        revision += 1
    }

    func noteAchievementCreated(_ id: AchievementID) {
        latest = .achievement(id)
        latestAchievementID = id
        revision += 1
    }

    func noteReelLinked(_ id: ReelID) {
        latest = .reelLinked(id)
        latestReelID = id
        revision += 1
    }

    func noteReelCreated(_ reel: Reel) {
        latest = .reel(reel)
        latestReelID = reel.id
        revision += 1
    }

    func noteStoryCreated(_ story: Story) {
        latest = .story(story)
        latestStoryID = story.id
        latestDeletedStoryID = nil
        revision += 1
    }

    func noteStoryDeleted(_ id: StoryID) {
        latest = .storyDeleted(id)
        latestDeletedStoryID = id
        revision += 1
    }

    func invalidate() {
        latest = nil
        latestPostID = nil
        latestAchievementID = nil
        latestReelID = nil
        latestStoryID = nil
        latestDeletedStoryID = nil
        revision = 0
    }
}
