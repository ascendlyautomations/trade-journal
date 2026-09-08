import XCTest
@testable import TradeTraxs

@MainActor
final class FeedVideoPlaybackCoordinatorTests: XCTestCase {
    func testOnlyOneClipActiveAtATime() {
        let coordinator = FeedVideoPlaybackCoordinator(storage: FeedClipStubStorage())
        let first = ReelID(rawValue: "reel-a")
        let second = ReelID(rawValue: "reel-b")

        coordinator.setClipVisible(first, visible: true)
        XCTAssertTrue(coordinator.isActive(first))
        XCTAssertFalse(coordinator.isActive(second))

        coordinator.setClipVisible(second, visible: true)
        XCTAssertFalse(coordinator.isActive(first))
        XCTAssertTrue(coordinator.isActive(second))
    }

    func testClipBecomesInactiveWhenScrolledOffscreen() {
        let coordinator = FeedVideoPlaybackCoordinator(storage: FeedClipStubStorage())
        let reelID = ReelID(rawValue: "reel-a")

        coordinator.setClipVisible(reelID, visible: true)
        coordinator.setClipVisible(reelID, visible: false)

        XCTAssertFalse(coordinator.isActive(reelID))
        XCTAssertTrue(coordinator.shouldShowPlayIndicator(for: reelID))
    }

    func testPauseAllClearsActiveClip() {
        let coordinator = FeedVideoPlaybackCoordinator(storage: FeedClipStubStorage())
        let reelID = ReelID(rawValue: "reel-a")

        coordinator.setClipVisible(reelID, visible: true)
        coordinator.pauseAll()

        XCTAssertFalse(coordinator.isActive(reelID))
    }

    func testManualPauseShowsPlayIndicatorWhileActive() {
        let coordinator = FeedVideoPlaybackCoordinator(storage: FeedClipStubStorage())
        let reel = ProfileClipFixtures.samples(owner: FeedFixtures.viewerID)[0]

        coordinator.setClipVisible(reel.id, visible: true)
        coordinator.togglePlayPause(for: reel)

        XCTAssertTrue(coordinator.isActive(reel.id))
        XCTAssertTrue(coordinator.shouldShowPlayIndicator(for: reel.id))
    }

    func testClipsExperienceStartsUnmutedAndSingleActiveClip() {
        let coordinator = FeedVideoPlaybackCoordinator(storage: FeedClipStubStorage())
        let samples = ProfileClipFixtures.samples(owner: FeedFixtures.viewerID)
        let first = samples[0]
        let second = samples[1]

        coordinator.beginClipsExperience()
        XCTAssertFalse(coordinator.isMuted)

        coordinator.setActiveClip(first)
        XCTAssertTrue(coordinator.isActive(first.id))

        coordinator.setActiveClip(second)
        XCTAssertFalse(coordinator.isActive(first.id))
        XCTAssertTrue(coordinator.isActive(second.id))
    }

    func testClipsExperienceEndRestoresMutedDefault() {
        let coordinator = FeedVideoPlaybackCoordinator(storage: FeedClipStubStorage())
        coordinator.beginClipsExperience()
        XCTAssertFalse(coordinator.isMuted)
        coordinator.endClipsExperience()
        XCTAssertTrue(coordinator.isMuted)
    }
}

private struct FeedClipStubStorage: ObjectStorageProviding {
    func upload(bucket: String, path: String, data: Data, contentType: String) async throws -> String {
        path
    }

    func download(bucket: String, path: String) async throws -> Data {
        Data()
    }

    func delete(bucket: String, path: String) async throws {}

    func publicURL(bucket: String, path: String) -> URL? {
        URL(string: "https://example.com/\(path)")
    }
}
