import XCTest
@testable import TradeTraxs

@MainActor
final class RelationshipStateTests: XCTestCase {
    private let viewerA = ProfileID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private let viewerB = ProfileID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
    private let target = ProfileID("cccccccc-cccc-cccc-cccc-cccccccccccc")

    override func setUp() {
        super.setUp()
        SessionDiskCache.clearAll()
        RelationshipWriteGeneration.resetForTesting()
        FollowMutationCoordinator.shared.invalidate()
    }

    override func tearDown() async throws {
        await SessionFollowingStore.shared.invalidate()
        SessionDiskCache.clearAll()
        RelationshipWriteGeneration.resetForTesting()
        FollowMutationCoordinator.shared.invalidate()
        try await super.tearDown()
    }

    func testCompleteFollowingDiskRoundTrip() async {
        let ids: Set<String> = ["follow-1", "follow-2"]
        await SessionFollowingStore.shared.seedComplete(viewerID: viewerA.rawValue, ids: ids)
        let generation = RelationshipWriteGeneration.bump(viewerID: viewerA)
        RelationshipFollowingPersistence.saveComplete(
            ids: Array(ids).sorted(),
            viewerID: viewerA,
            generation: generation
        )

        await SessionFollowingStore.shared.invalidate(viewerID: viewerA.rawValue)
        let loaded = RelationshipFollowingPersistence.loadComplete(for: viewerA)
        XCTAssertEqual(Set(loaded ?? []), ids)

        await FollowMutationCoordinator.shared.hydrateViewerFollowingRelationshipsIfNeeded(viewer: viewerA)
        let cached = await SessionFollowingStore.shared.cached(viewerID: viewerA.rawValue)
        XCTAssertEqual(cached, ids)
    }

    func testPartialPairwiseDoesNotImplyCompleteSet() async {
        await SessionFollowingStore.shared.seedPairwiseEdge(
            viewerID: viewerA.rawValue,
            targetID: target.rawValue,
            isFollowing: true
        )
        let cached = await SessionFollowingStore.shared.cached(viewerID: viewerA.rawValue)
        XCTAssertNil(cached)
        let knownTarget = await SessionFollowingStore.shared.knownIsFollowing(
            viewerID: viewerA.rawValue,
            targetID: target.rawValue
        )
        XCTAssertEqual(knownTarget, true)
        let unknown = await SessionFollowingStore.shared.knownIsFollowing(
            viewerID: viewerA.rawValue,
            targetID: "unknown-profile"
        )
        XCTAssertNil(unknown)
    }

    func testFollowPatchesMemoryAndDisk() async {
        let cache = DetailPresentationCache()
        configureCoordinator(cache: cache)
        cache.seedViewerFollowingIDs([])

        FollowMutationCoordinator.shared.applyEdgeChange(
            viewer: viewerA,
            target: target,
            isFollowing: true
        )
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(cache.viewerFollowEdge(for: target) == true)
        let disk = RelationshipFollowingPersistence.loadComplete(for: viewerA)
        XCTAssertTrue(disk?.contains(target.rawValue) == true)
    }

    func testUnfollowRemovesFromDisk() async {
        let cache = DetailPresentationCache()
        configureCoordinator(cache: cache)
        cache.seedViewerFollowingIDs([target])

        FollowMutationCoordinator.shared.applyEdgeChange(
            viewer: viewerA,
            target: target,
            isFollowing: true
        )
        FollowMutationCoordinator.shared.applyEdgeChange(
            viewer: viewerA,
            target: target,
            isFollowing: false
        )
        try? await Task.sleep(nanoseconds: 50_000_000)

        let disk = RelationshipFollowingPersistence.loadComplete(for: viewerA)
        XCTAssertFalse(disk?.contains(target.rawValue) ?? true)
    }

    func testFollowRequestIsNotFollowingInCompleteSet() async {
        let cache = DetailPresentationCache()
        configureCoordinator(cache: cache)
        cache.seedViewerFollowingIDs([])

        FollowMutationCoordinator.shared.applyFollowRequestPresentation(
            viewer: viewerA,
            target: target,
            isRequested: true
        )

        XCTAssertEqual(cache.viewerFollowRequested(for: target), true)
        XCTAssertEqual(cache.viewerFollowEdge(for: target), false)
        XCTAssertFalse(cache.viewerFollowingIDs()?.contains(target) ?? true)
    }

    func testViewerIsolationOnDisk() async {
        RelationshipFollowingPersistence.saveComplete(
            ids: ["secret"],
            viewerID: viewerA,
            generation: RelationshipWriteGeneration.bump(viewerID: viewerA)
        )
        XCTAssertNil(RelationshipFollowingPersistence.loadComplete(for: viewerB))
    }

    func testRapidFollowUnfollowNewestWins() async {
        let cache = DetailPresentationCache()
        configureCoordinator(cache: cache)
        cache.seedViewerFollowingIDs([])

        FollowMutationCoordinator.shared.applyEdgeChange(
            viewer: viewerA,
            target: target,
            isFollowing: true
        )
        FollowMutationCoordinator.shared.applyEdgeChange(
            viewer: viewerA,
            target: target,
            isFollowing: false
        )
        try? await Task.sleep(nanoseconds: 80_000_000)

        let disk = RelationshipFollowingPersistence.loadComplete(for: viewerA) ?? []
        XCTAssertFalse(disk.contains(target.rawValue))
    }

    private func configureCoordinator(cache: DetailPresentationCache) {
        FollowMutationCoordinator.shared.configure(
            detailCache: cache,
            currentUserProfile: CurrentUserProfileStore(
                profiles: CompositionRoot.bootstrapAppEnvironment().data.profiles,
                session: CompositionRoot.bootstrapAppEnvironment().data.session,
                imagePipeline: CompositionRoot.bootstrapAppEnvironment().data.imagePipeline,
                detailCache: cache
            )
        )
    }
}
