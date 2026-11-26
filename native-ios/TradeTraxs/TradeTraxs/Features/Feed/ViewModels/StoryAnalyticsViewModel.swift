import Foundation
import Observation

@Observable
@MainActor
final class StoryAnalyticsViewModel {
    enum Phase: Equatable {
        case loading
        case loaded(StoryInsights)
        case failed(String)
    }

    private(set) var phase: Phase = .loading

    private let storyID: StoryID
    private let feed: any FeedRepository
    private let detailCache: DetailPresentationCache

    init(storyID: StoryID, feed: any FeedRepository, detailCache: DetailPresentationCache) {
        self.storyID = storyID
        self.feed = feed
        self.detailCache = detailCache
    }

    func reload() {
        phase = .loading
    }

    func loadIfNeeded() async {
        guard case .loading = phase else { return }
        if storyID.rawValue.hasPrefix("dev-") {
            let insights = StoryInsightsFixtures.sample(for: storyID)
            seedProfiles(from: insights)
            phase = .loaded(insights)
            return
        }
        do {
            let insights = try await feed.storyInsights(id: storyID)
            seedProfiles(from: insights)
            phase = .loaded(insights)
        } catch {
            phase = .failed(ProfileSectionSupport.message(for: error))
        }
    }

    private func seedProfiles(from insights: StoryInsights) {
        for viewer in insights.viewers {
            detailCache.seed(viewer.profileStub)
        }
    }
}

enum StoryInsightsFixtures {
    static func sample(for storyID: StoryID) -> StoryInsights {
        let viewers = FollowListFixtures.followers(owner: FeedFixtures.viewerID).prefix(3).map { profile in
            StoryInsightsViewer(
                id: profile.id,
                username: profile.username,
                displayName: profile.displayName,
                avatarURL: profile.avatar?.id,
                viewedAt: Date().addingTimeInterval(-3600),
                liked: profile.username == "ada",
                replied: profile.username == "grace"
            )
        }
        return StoryInsights(
            storyID: storyID,
            viewCount: 12,
            likeCount: 3,
            replyCount: 2,
            viewers: Array(viewers)
        )
    }
}