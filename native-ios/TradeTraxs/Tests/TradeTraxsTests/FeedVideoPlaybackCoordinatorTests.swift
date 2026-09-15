import XCTest
@testable import TradeTraxs

@MainActor
final class FeedVideoPlaybackCoordinatorTests: XCTestCase {
    private var samples: [Reel] {
        ProfileClipFixtures.samples(owner: FeedFixtures.viewerID)
    }

    func testOnlyOneClipActiveAtATime() async {
        let coordinator = FeedVideoPlaybackCoordinator(storage: FeedClipStubStorage())
        let first = samples[0]
        let second = samples[1]

        coordinator.setClipVisible(first, visible: true)
        XCTAssertTrue(coordinator.isActive(first.id))
        XCTAssertFalse(coordinator.isActive(second.id))

        coordinator.setClipVisible(second, visible: true)
        XCTAssertTrue(coordinator.isActive(first.id), "Sticky owner keeps first while both fully visible")

        coordinator.updateInlineClipVisibility(reel: first, fraction: 0.2)
        coordinator.updateInlineClipVisibility(reel: second, fraction: 1.0)
        await coordinator.testing_drainInlineOwnership()

        XCTAssertFalse(coordinator.isActive(first.id))
        XCTAssertTrue(coordinator.isActive(second.id))
        XCTAssertEqual(coordinator.retainedPlayerCount, 1)
    }

    func testClipBecomesInactiveWhenScrolledOffscreen() async {
        let coordinator = FeedVideoPlaybackCoordinator(storage: FeedClipStubStorage())
        let reel = samples[0]

        coordinator.setClipVisible(reel, visible: true)
        coordinator.setClipVisible(reel, visible: false)
        await coordinator.testing_drainInlineOwnership()

        XCTAssertFalse(coordinator.isActive(reel.id))
        XCTAssertTrue(coordinator.shouldShowPlayIndicator(for: reel.id))
        XCTAssertLessThanOrEqual(coordinator.retainedPlayerCount, 1)
    }

    func testReleaseAllPlayersClearsActiveClipAndRetainedPlayers() {
        let coordinator = FeedVideoPlaybackCoordinator(storage: FeedClipStubStorage())
        let reel = samples[0]

        coordinator.setClipVisible(reel, visible: true)
        coordinator.releaseAllPlayers()

        XCTAssertFalse(coordinator.isActive(reel.id))
        XCTAssertEqual(coordinator.retainedPlayerCount, 0)
    }

    func testManualPauseShowsPlayIndicatorWhileActive() {
        let coordinator = FeedVideoPlaybackCoordinator(storage: FeedClipStubStorage())
        let reel = samples[0]

        coordinator.setClipVisible(reel, visible: true)
        coordinator.togglePlayPause(for: reel)

        XCTAssertTrue(coordinator.isActive(reel.id))
        XCTAssertTrue(coordinator.shouldShowPlayIndicator(for: reel.id))
        XCTAssertEqual(coordinator.retainedPlayerCount, 1)
    }

    func testClipsExperienceStartsUnmutedAndSingleActiveClip() {
        let coordinator = FeedVideoPlaybackCoordinator(storage: FeedClipStubStorage())
        let first = samples[0]
        let second = samples[1]

        coordinator.beginClipsExperience()
        XCTAssertFalse(coordinator.isMuted)

        coordinator.setActiveClip(first)
        XCTAssertTrue(coordinator.isActive(first.id))
        XCTAssertEqual(coordinator.retainedPlayerCount, 1)

        coordinator.setActiveClip(second)
        XCTAssertFalse(coordinator.isActive(first.id))
        XCTAssertTrue(coordinator.isActive(second.id))
        XCTAssertEqual(coordinator.retainedPlayerCount, 1)
    }

    func testClipsNeighborPrefetchRetainsAtMostTwoPlayers() {
        let coordinator = FeedVideoPlaybackCoordinator(storage: FeedClipStubStorage())
        let first = samples[0]
        let second = samples[1]
        let third = samples[2]

        coordinator.beginClipsExperience()
        coordinator.setActiveClip(first, atIndex: 0)
        coordinator.prepareNeighborClip(second, atIndex: 1)

        XCTAssertEqual(coordinator.retainedPlayerCount, 2)

        coordinator.setActiveClip(second, atIndex: 1)
        XCTAssertTrue(coordinator.isActive(second.id))
        XCTAssertLessThanOrEqual(coordinator.retainedPlayerCount, 2)

        coordinator.prepareNeighborClip(third, atIndex: 2)
        XCTAssertLessThanOrEqual(coordinator.retainedPlayerCount, 2)
        XCTAssertNil(coordinator.player(for: first.id))
    }

    func testClipsExperienceEndReleasesPlayersAndRestoresMutedDefault() {
        let coordinator = FeedVideoPlaybackCoordinator(storage: FeedClipStubStorage())
        coordinator.beginClipsExperience()
        coordinator.setActiveClip(samples[0])
        XCTAssertFalse(coordinator.isMuted)
        XCTAssertEqual(coordinator.retainedPlayerCount, 1)

        coordinator.endClipsExperience()
        XCTAssertTrue(coordinator.isMuted)
        XCTAssertEqual(coordinator.retainedPlayerCount, 0)
    }

    func testPlayerForDoesNotCreatePlayer() {
        let coordinator = FeedVideoPlaybackCoordinator(storage: FeedClipStubStorage())
        let reelID = samples[0].id

        XCTAssertNil(coordinator.player(for: reelID))
        XCTAssertEqual(coordinator.retainedPlayerCount, 0)
    }

    func testStalePreparationCannotRetainPlayerAfterActiveChanges() async {
        let coordinator = FeedVideoPlaybackCoordinator(storage: FeedClipStubStorage())
        let first = samples[0]
        let second = samples[1]

        coordinator.setClipVisible(first, visible: true)
        XCTAssertEqual(coordinator.retainedPlayerCount, 1)

        coordinator.updateInlineClipVisibility(reel: first, fraction: 0.2)
        coordinator.setClipVisible(second, visible: true)
        await coordinator.testing_drainInlineOwnership()

        XCTAssertTrue(coordinator.isActive(second.id))
        XCTAssertEqual(coordinator.retainedPlayerCount, 1)
        XCTAssertNil(coordinator.player(for: first.id))
    }

    func testStickyOwnerRetainsCurrentClipWhileAboveKeepThreshold() {
        let coordinator = FeedVideoPlaybackCoordinator(storage: FeedClipStubStorage())
        let first = samples[0]
        let second = samples[1]

        coordinator.updateInlineClipVisibility(reel: first, fraction: 0.9)
        XCTAssertTrue(coordinator.isActive(first.id))

        coordinator.updateInlineClipVisibility(reel: second, fraction: 0.58)
        coordinator.updateInlineClipVisibility(reel: first, fraction: 0.42)
        XCTAssertTrue(coordinator.isActive(first.id))
    }

    func testStickyOwnerTransfersOnlyAfterCurrentFallsBelowKeep() async {
        let coordinator = FeedVideoPlaybackCoordinator(storage: FeedClipStubStorage())
        let first = samples[0]
        let second = samples[1]

        coordinator.updateInlineClipVisibility(reel: first, fraction: 0.9)
        coordinator.updateInlineClipVisibility(reel: second, fraction: 0.95)
        XCTAssertTrue(coordinator.isActive(first.id))

        coordinator.updateInlineClipVisibility(reel: first, fraction: 0.2)
        coordinator.updateInlineClipVisibility(reel: second, fraction: 0.95)
        await coordinator.testing_drainInlineOwnership()

        XCTAssertTrue(coordinator.isActive(second.id))
        XCTAssertEqual(coordinator.retainedPlayerCount, 1)
    }

    func testPosterStaysVisibleUntilVideoFrameIsDisplayed() {
        let coordinator = FeedVideoPlaybackCoordinator(storage: FeedClipStubStorage())
        let reel = samples[0]

        coordinator.setClipVisible(reel, visible: true)
        XCTAssertFalse(coordinator.shouldHidePoster(for: reel.id))

        coordinator.noteVideoReadyForDisplay(reel.id)
        XCTAssertFalse(
            coordinator.shouldHidePoster(for: reel.id),
            "Poster remains until live player is showing"
        )
    }
}

private struct FeedClipStubStorage: ObjectStorageProviding {
    func upload(bucket: String, path: String, data: Data, contentType: String, cacheControl: String? = nil) async throws -> String {
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
