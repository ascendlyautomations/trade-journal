import XCTest
@testable import TradeTraxs

final class GettingStartedChecklistTests: XCTestCase {
    func testMilestoneCelebratesOnlyTheIncompleteToCompleteTransition() {
        XCTAssertFalse(
            GettingStartedCompletionMilestone.shouldCelebrate(
                hasEstablishedBaseline: false,
                previousAllComplete: false,
                nextAllComplete: true,
                hasSeenCompletionPopup: false
            )
        )
        XCTAssertTrue(
            GettingStartedCompletionMilestone.shouldCelebrate(
                hasEstablishedBaseline: true,
                previousAllComplete: false,
                nextAllComplete: true,
                hasSeenCompletionPopup: false
            )
        )
        XCTAssertFalse(
            GettingStartedCompletionMilestone.shouldCelebrate(
                hasEstablishedBaseline: true,
                previousAllComplete: false,
                nextAllComplete: true,
                hasSeenCompletionPopup: true
            )
        )
        XCTAssertFalse(
            GettingStartedCompletionMilestone.shouldCelebrate(
                hasEstablishedBaseline: true,
                previousAllComplete: true,
                nextAllComplete: true,
                hasSeenCompletionPopup: false
            )
        )
        let onboardingOnly = GettingStartedChecklistPolicy.computeProgress(
            from: GettingStartedSignals(
                onboardingCompleted: true,
                hasSeenGettingStartedIntro: false,
                hasSeenOnboardingCompletePopup: false,
                tradeCount: 0,
                hasCreatedProfilePost: false,
                profilePostCount: 0,
                followCount: 0,
                hasEverJoinedOtherRoom: false,
                hasPublicTrade: false,
                hasCompletedDailyCheckIn: false,
                firstPrivateTradeID: nil
            )
        )
        XCTAssertFalse(onboardingOnly.allComplete)
        XCTAssertFalse(
            GettingStartedCompletionMilestone.shouldCelebrate(
                hasEstablishedBaseline: true,
                previousAllComplete: false,
                nextAllComplete: onboardingOnly.allComplete,
                hasSeenCompletionPopup: false
            )
        )
    }

    func testWriteReviewURLRequiresConfiguredAppStoreID() {
        XCTAssertNil(AppStoreProductReview.writeReviewURL(appStoreID: nil))
        XCTAssertNil(AppStoreProductReview.writeReviewURL(appStoreID: "not-an-id"))
        XCTAssertEqual(
            AppStoreProductReview.writeReviewURL(appStoreID: "1234567890")?.absoluteString,
            "https://apps.apple.com/app/id1234567890?action=write-review"
        )
        XCTAssertEqual(
            AppStoreProductReview.writeReviewURL()?.absoluteString,
            "https://apps.apple.com/app/id6808723069?action=write-review"
        )
    }

    func testFreshUserAfterPhase1HasProfileCompleteOnly() {
        let signals = GettingStartedSignals(
            onboardingCompleted: true,
            hasSeenGettingStartedIntro: false,
            hasSeenOnboardingCompletePopup: false,
            tradeCount: 0,
            hasCreatedProfilePost: false,
            profilePostCount: 0,
            followCount: 0,
            hasEverJoinedOtherRoom: false,
            hasPublicTrade: false,
            hasCompletedDailyCheckIn: false,
            firstPrivateTradeID: nil
        )
        let progress = GettingStartedChecklistPolicy.computeProgress(from: signals)
        XCTAssertTrue(progress.tasks.first(where: { $0.id == .profile })?.isComplete == true)
        XCTAssertEqual(progress.completedCount, 1)
        XCTAssertFalse(progress.allComplete)
    }

    func testTradeCountCompletesFirstTrade() {
        var signals = GettingStartedSignals.empty
        signals.onboardingCompleted = true
        signals.tradeCount = 1
        let progress = GettingStartedChecklistPolicy.computeProgress(from: signals)
        XCTAssertTrue(progress.tasks.first(where: { $0.id == .trade })?.isComplete == true)
    }

    func testFollowCountCompletesFollow() {
        var signals = GettingStartedSignals.empty
        signals.onboardingCompleted = true
        signals.followCount = 2
        let progress = GettingStartedChecklistPolicy.computeProgress(from: signals)
        XCTAssertTrue(progress.tasks.first(where: { $0.id == .follow })?.isComplete == true)
    }

    func testRoomSignalCompletesRoomTask() {
        var signals = GettingStartedSignals.empty
        signals.onboardingCompleted = true
        signals.hasEverJoinedOtherRoom = true
        let progress = GettingStartedChecklistPolicy.computeProgress(from: signals)
        XCTAssertTrue(progress.tasks.first(where: { $0.id == .room })?.isComplete == true)
    }

    func testPublicTradeSignalCompletesPublicTask() {
        var signals = GettingStartedSignals.empty
        signals.onboardingCompleted = true
        signals.hasPublicTrade = true
        let progress = GettingStartedChecklistPolicy.computeProgress(from: signals)
        XCTAssertTrue(progress.tasks.first(where: { $0.id == .publicTrade })?.isComplete == true)
    }

    func testProfilePostCountCompletesPostTask() {
        var signals = GettingStartedSignals.empty
        signals.onboardingCompleted = true
        signals.hasCreatedProfilePost = true
        signals.profilePostCount = 1
        let progress = GettingStartedChecklistPolicy.computeProgress(from: signals)
        XCTAssertTrue(progress.tasks.first(where: { $0.id == .post })?.isComplete == true)
    }

    func testPublicTradeDoesNotCompletePostTask() {
        var signals = GettingStartedSignals.empty
        signals.onboardingCompleted = true
        signals.tradeCount = 1
        signals.hasPublicTrade = true
        let progress = GettingStartedChecklistPolicy.computeProgress(from: signals)
        XCTAssertTrue(progress.tasks.first(where: { $0.id == .publicTrade })?.isComplete == true)
        XCTAssertFalse(progress.tasks.first(where: { $0.id == .post })?.isComplete == true)
    }

    func testServerReconcileClearsFalsePostCompletion() {
        var effective = GettingStartedSignals.empty
        effective.hasCreatedProfilePost = true
        effective.profilePostCount = 1
        let server = GettingStartedSignals.empty
        let repaired = GettingStartedContentSignalReconcile.reconcilePostAgainstServer(
            effective: effective,
            server: server,
            trustLocalProfilePostHint: false
        )
        XCTAssertFalse(repaired.hasCreatedProfilePost)
        XCTAssertEqual(repaired.profilePostCount, 0)
    }

    func testLocalPostHintPreservesOptimisticPostUntilRpcConfirms() {
        var effective = GettingStartedSignals.empty
        effective.hasCreatedProfilePost = true
        effective.profilePostCount = 1
        let server = GettingStartedSignals.empty
        let retained = GettingStartedContentSignalReconcile.reconcilePostAgainstServer(
            effective: effective,
            server: server,
            trustLocalProfilePostHint: true
        )
        XCTAssertTrue(retained.hasCreatedProfilePost)
    }

    func testMonotonicMergeNeverRegressesRoomCompletion() {
        let prior = GettingStartedSignals(
            onboardingCompleted: true,
            hasSeenGettingStartedIntro: false,
            hasSeenOnboardingCompletePopup: false,
            tradeCount: 0,
            hasCreatedProfilePost: false,
            profilePostCount: 0,
            followCount: 0,
            hasEverJoinedOtherRoom: true,
            hasPublicTrade: false,
            hasCompletedDailyCheckIn: false,
            firstPrivateTradeID: nil
        )
        var stale = prior
        stale.hasEverJoinedOtherRoom = false
        let merged = GettingStartedSignalsMonotonic.merge(prior: prior, server: stale)
        XCTAssertTrue(merged.hasEverJoinedOtherRoom)
    }

    func testDailyCheckInSignalCompletesDailyCheckInTask() {
        var signals = GettingStartedSignals.empty
        signals.onboardingCompleted = true
        signals.hasCompletedDailyCheckIn = true
        let progress = GettingStartedChecklistPolicy.computeProgress(from: signals)
        XCTAssertTrue(progress.tasks.first(where: { $0.id == .dailyCheckIn })?.isComplete == true)
    }

    func testAllSevenCompleteMarksAllComplete() {
        let signals = GettingStartedSignals(
            onboardingCompleted: true,
            hasSeenGettingStartedIntro: true,
            hasSeenOnboardingCompletePopup: true,
            tradeCount: 3,
            hasCreatedProfilePost: true,
            profilePostCount: 1,
            followCount: 2,
            hasEverJoinedOtherRoom: true,
            hasPublicTrade: true,
            hasCompletedDailyCheckIn: true,
            firstPrivateTradeID: TradeID("trade-1")
        )
        let progress = GettingStartedChecklistPolicy.computeProgress(from: signals)
        XCTAssertEqual(progress.completedCount, 7)
        XCTAssertEqual(progress.totalCount, 7)
        XCTAssertTrue(progress.allComplete)
    }

    func testDashboardStaysVisibleAfterFirstTradeWhileTasksRemain() {
        let signals = GettingStartedSignals(
            onboardingCompleted: true,
            hasSeenGettingStartedIntro: false,
            hasSeenOnboardingCompletePopup: false,
            tradeCount: 1,
            hasCreatedProfilePost: false,
            profilePostCount: 0,
            followCount: 0,
            hasEverJoinedOtherRoom: false,
            hasPublicTrade: false,
            hasCompletedDailyCheckIn: false,
            firstPrivateTradeID: nil
        )
        let progress = GettingStartedChecklistPolicy.computeProgress(from: signals)
        XCTAssertEqual(progress.tasks.first { $0.id == .trade }?.isComplete, true)
        XCTAssertFalse(progress.allComplete)
        XCTAssertTrue(
            GettingStartedChecklistPolicy.shouldShowDashboardCard(
                userID: "user-1",
                signals: signals,
                progress: progress,
                sessionDismissed: false
            )
        )
    }

    func testDashboardHidesWhenAllTasksComplete() {
        let signals = GettingStartedSignals(
            onboardingCompleted: true,
            hasSeenGettingStartedIntro: true,
            hasSeenOnboardingCompletePopup: false,
            tradeCount: 5,
            hasCreatedProfilePost: true,
            profilePostCount: 1,
            followCount: 2,
            hasEverJoinedOtherRoom: true,
            hasPublicTrade: true,
            hasCompletedDailyCheckIn: true,
            firstPrivateTradeID: TradeID("trade-1")
        )
        let progress = GettingStartedChecklistPolicy.computeProgress(from: signals)
        XCTAssertTrue(progress.allComplete)
        XCTAssertFalse(
            GettingStartedChecklistPolicy.shouldShowDashboardCard(
                userID: "user-1",
                signals: signals,
                progress: progress,
                sessionDismissed: false
            )
        )
    }

    func testIncompleteChecklistStaysVisibleWhenCompletionPopupWasSeen() {
        let signals = GettingStartedSignals(
            onboardingCompleted: true,
            hasSeenGettingStartedIntro: true,
            hasSeenOnboardingCompletePopup: true,
            tradeCount: 0,
            hasCreatedProfilePost: false,
            profilePostCount: 0,
            followCount: 0,
            hasEverJoinedOtherRoom: false,
            hasPublicTrade: false,
            hasCompletedDailyCheckIn: false,
            firstPrivateTradeID: nil
        )
        let progress = GettingStartedChecklistPolicy.computeProgress(from: signals)
        XCTAssertFalse(progress.allComplete)
        XCTAssertTrue(
            GettingStartedChecklistPolicy.shouldShowDashboardCard(
                userID: "user-1",
                signals: signals,
                progress: progress,
                sessionDismissed: true
            )
        )
    }

    func testNeedsServerCompletionReconciliationWhenAllCompleteWithoutFlag() {
        let signals = GettingStartedSignals(
            onboardingCompleted: true,
            hasSeenGettingStartedIntro: true,
            hasSeenOnboardingCompletePopup: false,
            tradeCount: 1,
            hasCreatedProfilePost: true,
            profilePostCount: 1,
            followCount: 1,
            hasEverJoinedOtherRoom: true,
            hasPublicTrade: true,
            hasCompletedDailyCheckIn: true,
            firstPrivateTradeID: nil
        )
        let progress = GettingStartedChecklistPolicy.computeProgress(from: signals)
        XCTAssertTrue(
            GettingStartedChecklistPolicy.needsServerCompletionReconciliation(
                signals: signals,
                progress: progress
            )
        )
    }

    func testIntroPopupDisabled() {
        XCTAssertFalse(
            GettingStartedChecklistPolicy.shouldShowIntroPopup(
                onboardingCompleted: true,
                hasSeenGettingStartedIntro: false
            )
        )
    }

    func testSignalsDecoderMapsRpcWireShape() throws {
        let json = """
        {
          "onboarding_completed": true,
          "has_seen_getting_started_intro": false,
          "has_seen_onboarding_complete_popup": false,
          "trade_count": 2,
          "profile_post_count": 1,
          "has_created_profile_post": true,
          "follow_count": 3,
          "has_ever_joined_other_room": true,
          "has_public_trade": false,
          "has_completed_daily_check_in": true,
          "first_private_trade_id": "abc-123"
        }
        """
        let signals = try GettingStartedSignalsDecoder.decode(Data(json.utf8))
        XCTAssertTrue(signals.onboardingCompleted)
        XCTAssertEqual(signals.tradeCount, 2)
        XCTAssertEqual(signals.profilePostCount, 1)
        XCTAssertTrue(signals.hasCreatedProfilePost)
        XCTAssertEqual(signals.followCount, 3)
        XCTAssertTrue(signals.hasEverJoinedOtherRoom)
        XCTAssertTrue(signals.hasCompletedDailyCheckIn)
        XCTAssertEqual(signals.firstPrivateTradeID?.rawValue, "abc-123")
    }
}

@MainActor
final class GettingStartedStoreTests: XCTestCase {
    override func setUp() {
        BackendV2FeatureFlags.resetFlagsForTests()
        BackendV2FeatureFlags.setFlagForTests(.gettingStarted, enabled: true)
        GettingStartedStore.shared.invalidate()
    }

    override func tearDown() {
        GettingStartedStore.shared.invalidate()
        BackendV2FeatureFlags.resetFlagsForTests()
    }

    func testLogoutClearsPreviousUserProgress() async {
        let store = GettingStartedStore.shared
        store.configure(
            rpc: FixtureGettingStartedRPC(json: Self.sampleJSON(completed: false)),
            session: FixedGettingStartedSession(userID: UserID("user-a")),
            realtimeHub: nil
        )
        store.refresh(fromUserAction: false)
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertTrue(store.signalsReady)
        XCTAssertEqual(store.progress.completedCount, 1)

        store.invalidate()
        XCTAssertFalse(store.signalsReady)
        XCTAssertEqual(store.progress.completedCount, 0)
    }

    func testRefreshUsesSingleFlightForConcurrentCallers() async throws {
        BackendV2FeatureFlags.setFlagForTests(.gettingStarted, enabled: true)
        let rpc = CountingGettingStartedRPC(json: Self.sampleJSON(completed: false))
        GettingStartedStore.shared.configure(
            rpc: rpc,
            session: FixedGettingStartedSession(userID: UserID("user-b")),
            realtimeHub: nil
        )

        async let first: Void = GettingStartedStore.shared.refresh(fromUserAction: false)
        async let second: Void = GettingStartedStore.shared.refresh(fromUserAction: false)
        _ = await (first, second)

        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(rpc.callCount, 1)
    }

    func testCompletionCelebrationRequiresIncompleteToCompleteTransition() async throws {
        let userID = "gs-completion-\(UUID().uuidString)"
        defer {
            GettingStartedCompletionPersistence.clear(userID: userID)
            GettingStartedPreferences.clearCompletionReviewRequested(userID: userID)
        }
        let store = GettingStartedStore.shared
        store.configure(
            rpc: FixtureGettingStartedRPC(json: Self.sampleJSON(completed: false)),
            session: FixedGettingStartedSession(userID: UserID(userID)),
            realtimeHub: nil
        )
        store.refresh(fromUserAction: false)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(store.showsGettingStartedCompletion)

        store.patchSignals(GettingStartedLocalPatches(onboardingCompleted: true))
        XCTAssertFalse(store.progress.allComplete)
        XCTAssertFalse(store.showsGettingStartedCompletion)

        var remaining = GettingStartedLocalPatches()
        remaining.tradeCountDelta = 1
        remaining.markCreatedProfilePost = true
        remaining.markFollowed = true
        remaining.markJoinedOtherRoom = true
        remaining.markPublicTrade = true
        remaining.markDailyCheckInCompleted = true
        store.patchSignals(remaining)

        XCTAssertTrue(store.progress.allComplete)
        XCTAssertTrue(store.showsGettingStartedCompletion)
        XCTAssertTrue(store.signals.hasSeenOnboardingCompletePopup)
        XCTAssertTrue(store.consumeReviewRequestAfterCompletion())
        XCTAssertFalse(store.consumeReviewRequestAfterCompletion())
        XCTAssertTrue(GettingStartedPreferences.hasRequestedCompletionReview(userID: userID))

        store.invalidate()
        store.configure(
            rpc: FixtureGettingStartedRPC(json: Self.sampleJSON(completed: true, tradeCount: 1)),
            session: FixedGettingStartedSession(userID: UserID(userID)),
            realtimeHub: nil
        )
        store.refresh(fromUserAction: false)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(store.showsGettingStartedCompletion)
    }

    func testAlreadyCompleteBaselineDoesNotCelebrate() async throws {
        let userID = "gs-already-complete-\(UUID().uuidString)"
        defer { GettingStartedCompletionPersistence.clear(userID: userID) }
        let store = GettingStartedStore.shared
        store.configure(
            rpc: FixtureGettingStartedRPC(json: Self.allCompleteJSON(seenPopup: false)),
            session: FixedGettingStartedSession(userID: UserID(userID)),
            realtimeHub: nil
        )
        store.refresh(fromUserAction: false)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(store.progress.allComplete)
        XCTAssertFalse(store.showsGettingStartedCompletion)
    }

    func testUserActionRefreshUpdatesProgress() async throws {
        let rpc = MutableGettingStartedRPC(
            json: Self.sampleJSON(tradeCount: 0),
            updatedJSON: Self.sampleJSON(tradeCount: 1)
        )
        GettingStartedStore.shared.configure(
            rpc: rpc,
            session: FixedGettingStartedSession(userID: UserID("user-c")),
            realtimeHub: nil
        )
        GettingStartedStore.shared.loadIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(GettingStartedStore.shared.progress.completedCount, 1)

        GettingStartedRefreshCenter.noteEligibleUserAction()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(GettingStartedStore.shared.progress.tasks.first(where: { $0.id == .trade })?.isComplete == true)
    }

    private static func sampleJSON(
        completed: Bool = false,
        tradeCount: Int = 0
    ) -> String {
        """
        {
          "onboarding_completed": true,
          "has_seen_getting_started_intro": false,
          "has_seen_onboarding_complete_popup": \(completed),
          "trade_count": \(tradeCount),
          "profile_post_count": 0,
          "follow_count": 0,
          "has_ever_joined_other_room": false,
          "has_public_trade": false,
          "has_completed_daily_check_in": false,
          "first_private_trade_id": null
        }
        """
    }

    private static func allCompleteJSON(seenPopup: Bool) -> String {
        """
        {
          "onboarding_completed": true,
          "has_seen_getting_started_intro": true,
          "has_seen_onboarding_complete_popup": \(seenPopup),
          "trade_count": 1,
          "profile_post_count": 1,
          "has_created_profile_post": true,
          "follow_count": 1,
          "has_ever_joined_other_room": true,
          "has_public_trade": true,
          "has_completed_daily_check_in": true,
          "first_private_trade_id": null
        }
        """
    }
}

private struct FixedGettingStartedSession: SessionProviding {
    let userID: UserID
    var currentUserID: UserID? { get async { userID } }
    var accessToken: String? { get async { "token" } }
}

private final class FixtureGettingStartedRPC: RPCClient, @unchecked Sendable {
    let json: String
    init(json: String) { self.json = json }
    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        Data(json.utf8)
    }
    func call(functionName: String, jsonBody: Data) async throws -> Data {
        Data(json.utf8)
    }
}

private final class CountingGettingStartedRPC: RPCClient, @unchecked Sendable {
    let json: String
    private(set) var callCount = 0
    init(json: String) { self.json = json }
    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        callCount += 1
        try await Task.sleep(nanoseconds: 100_000_000)
        return Data(json.utf8)
    }
    func call(functionName: String, jsonBody: Data) async throws -> Data {
        callCount += 1
        try await Task.sleep(nanoseconds: 100_000_000)
        return Data(json.utf8)
    }
}

private final class MutableGettingStartedRPC: RPCClient, @unchecked Sendable {
    var json: String
    let updatedJSON: String
    private var calls = 0
    init(json: String, updatedJSON: String) {
        self.json = json
        self.updatedJSON = updatedJSON
    }
    func call(functionName: String, parameters: [String: String]) async throws -> Data {
        try await respond()
    }
    func call(functionName: String, jsonBody: Data) async throws -> Data {
        try await respond()
    }
    private func respond() async throws -> Data {
        calls += 1
        let payload = calls == 1 ? json : updatedJSON
        try await Task.sleep(nanoseconds: 50_000_000)
        return Data(payload.utf8)
    }
}
