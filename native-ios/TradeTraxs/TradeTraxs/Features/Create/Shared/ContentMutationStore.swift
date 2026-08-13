import Foundation
import Observation

/// Broadcasts Post / Achievement / Clip mutations so Feed + Profile refresh without polling.
@Observable
@MainActor
final class ContentMutationStore {
    static let shared = ContentMutationStore()

    private(set) var revision: Int = 0
    private(set) var latestPostID: PostID?
    private(set) var latestAchievementID: AchievementID?
    private(set) var latestReelID: ReelID?

    private init() {}

    func notePostCreated(_ id: PostID) {
        latestPostID = id
        revision += 1
    }

    func noteAchievementCreated(_ id: AchievementID) {
        latestAchievementID = id
        revision += 1
    }

    func noteReelLinked(_ id: ReelID) {
        latestReelID = id
        revision += 1
    }

    func noteReelCreated(_ id: ReelID) {
        latestReelID = id
        revision += 1
    }

    func invalidate() {
        latestPostID = nil
        latestAchievementID = nil
        latestReelID = nil
        revision = 0
    }
}
