import XCTest
@testable import TradeTraxs

final class RealtimeRouteLifecycleTests: XCTestCase {
    private func makeProvider() -> LiveSupabaseRealtimeProvider {
        let configuration = AppConfiguration(
            buildConfiguration: .debug,
            apiBaseURL: nil,
            supabaseURL: URL(string: "https://example.supabase.co"),
            supabaseAnonKey: "anon",
            appDisplayName: "TradeTraxs"
        )
        return LiveSupabaseRealtimeProvider(configuration: configuration)
    }

    private func settleRegistration() async {
        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    private func waitForConsumers(on provider: LiveSupabaseRealtimeProvider, routeKey: String, count: Int) async {
        _ = await provider.testing_waitForConsumerCount(routeKey: routeKey, minimum: count)
    }

    func testTwoConsumersShareOneRouteUntilFinalRelease() async {
        let provider = makeProvider()
        let filter = "user_id=eq.shared-route-author"
        let routeKey = "social-entity:\(SocialEntityRealtimeTable.stableRouteSuffix(table: .posts, key: filter))"

        let watchA = provider.watchSocialEntityChanges(
            table: .posts,
            filter: filter,
            accessToken: nil,
            debugOwner: "FeedA"
        )
        await waitForConsumers(on: provider, routeKey: routeKey, count: 1)
        let watchB = provider.watchSocialEntityChanges(
            table: .posts,
            filter: filter,
            accessToken: nil,
            debugOwner: "FeedB"
        )
        await waitForConsumers(on: provider, routeKey: routeKey, count: 2)

        let both = provider.testing_routeSnapshot(routeKey: routeKey)
        XCTAssertEqual(both.consumerCount, 2)
        XCTAssertTrue(both.isJoined)

        await provider.releaseWatch(watchA.consumer)
        await waitForConsumers(on: provider, routeKey: routeKey, count: 1)

        let afterA = provider.testing_routeSnapshot(routeKey: routeKey)
        XCTAssertEqual(afterA.consumerCount, 1)
        XCTAssertTrue(afterA.isJoined)

        let signal = SocialEntityRealtimeEvent(
            table: .posts,
            mutation: .update,
            entityID: "post-shared",
            authorID: "shared-route-author",
            eventRowID: "post-shared",
            payload: .init()
        )
        let received = expectation(description: "consumer B receives event")
        let drain = Task {
            for await _ in watchB.events {
                received.fulfill()
                break
            }
        }
        provider.testing_injectSocialEntitySignal(routeKey: routeKey, signal: signal)
        await fulfillment(of: [received], timeout: 2.0)
        drain.cancel()

        await provider.releaseWatch(watchB.consumer)
        await waitForConsumers(on: provider, routeKey: routeKey, count: 0)

        let afterB = provider.testing_routeSnapshot(routeKey: routeKey)
        XCTAssertEqual(afterB.consumerCount, 0)
        XCTAssertFalse(afterB.isJoined)
        _ = watchA
    }

    func testReconnectSpecStaysSingleRouteWithMultipleConsumers() async {
        let provider = makeProvider()
        provider.testing_resetRegistryLifecycleCounters()
        let filter = "user_id=eq.lifecycle-test-author"
        let routeKey = "social-entity:\(SocialEntityRealtimeTable.stableRouteSuffix(table: .posts, key: filter))"

        let watchA = provider.watchSocialEntityChanges(
            table: .posts,
            filter: filter,
            accessToken: nil,
            debugOwner: "FeedA"
        )
        await waitForConsumers(on: provider, routeKey: routeKey, count: 1)
        let watchB = provider.watchSocialEntityChanges(
            table: .posts,
            filter: filter,
            accessToken: nil,
            debugOwner: "FeedB"
        )
        await waitForConsumers(on: provider, routeKey: routeKey, count: 2)

        let snapshot = provider.testing_routeSnapshot(routeKey: routeKey)
        XCTAssertEqual(snapshot.consumerCount, 2)
        XCTAssertEqual(snapshot.activeRouteCount, 1)
        XCTAssertTrue(snapshot.isJoined)
        XCTAssertEqual(provider.testing_registryJoinCount(), 1)
        XCTAssertEqual(provider.testing_registryLeaveCount(), 0)
        _ = watchA
        _ = watchB
    }

    func testDuplicateRetainSameHandleIsNoOp() async {
        let provider = makeProvider()
        provider.testing_resetRegistryLifecycleCounters()
        let filter = "user_id=eq.duplicate-retain-author"
        let routeKey = "social-entity:\(SocialEntityRealtimeTable.stableRouteSuffix(table: .posts, key: filter))"

        let watch = provider.watchSocialEntityChanges(
            table: .posts,
            filter: filter,
            accessToken: nil,
            debugOwner: "Once"
        )
        await waitForConsumers(on: provider, routeKey: routeKey, count: 1)
        XCTAssertEqual(provider.testing_registryJoinCount(), 1)

        await provider.testing_simulateDuplicateSocialEntityRetain(watch.consumer)
        let snapshot = provider.testing_routeSnapshot(routeKey: routeKey)
        XCTAssertEqual(snapshot.consumerCount, 1)
        XCTAssertEqual(provider.testing_registryJoinCount(), 1)
    }

    func testDuplicateReleaseSameHandleIsNoOp() async {
        let provider = makeProvider()
        provider.testing_resetRegistryLifecycleCounters()
        let filter = "user_id=eq.duplicate-release-author"
        let routeKey = "social-entity:\(SocialEntityRealtimeTable.stableRouteSuffix(table: .posts, key: filter))"

        let watch = provider.watchSocialEntityChanges(
            table: .posts,
            filter: filter,
            accessToken: nil,
            debugOwner: "Once"
        )
        await waitForConsumers(on: provider, routeKey: routeKey, count: 1)

        await provider.releaseWatch(watch.consumer)
        await provider.releaseWatch(watch.consumer)
        await provider.releaseWatch(watch.consumer)

        let snapshot = provider.testing_routeSnapshot(routeKey: routeKey)
        XCTAssertEqual(snapshot.consumerCount, 0)
        XCTAssertFalse(snapshot.isJoined)
        XCTAssertEqual(provider.testing_registryLeaveCount(), 1)
    }

    func testTwoDifferentConsumersOnePhysicalJoinAndLeave() async {
        let provider = makeProvider()
        provider.testing_resetRegistryLifecycleCounters()
        let filter = "user_id=eq.two-consumer-author"
        let routeKey = "social-entity:\(SocialEntityRealtimeTable.stableRouteSuffix(table: .posts, key: filter))"

        let watchA = provider.watchSocialEntityChanges(
            table: .posts,
            filter: filter,
            accessToken: nil,
            debugOwner: "A"
        )
        await waitForConsumers(on: provider, routeKey: routeKey, count: 1)
        XCTAssertEqual(provider.testing_registryJoinCount(), 1)

        let watchB = provider.watchSocialEntityChanges(
            table: .posts,
            filter: filter,
            accessToken: nil,
            debugOwner: "B"
        )
        await waitForConsumers(on: provider, routeKey: routeKey, count: 2)
        XCTAssertEqual(provider.testing_registryJoinCount(), 1)

        await provider.releaseWatch(watchA.consumer)
        await waitForConsumers(on: provider, routeKey: routeKey, count: 1)
        XCTAssertEqual(provider.testing_registryLeaveCount(), 0)

        await provider.releaseWatch(watchB.consumer)
        await waitForConsumers(on: provider, routeKey: routeKey, count: 0)
        XCTAssertEqual(provider.testing_registryLeaveCount(), 1)
    }

    func testDisconnectClearsAllRoutesAndConsumers() async {
        let provider = makeProvider()
        let filter = "user_id=eq.disconnect-test-author"
        let entityRoute = "social-entity:\(SocialEntityRealtimeTable.stableRouteSuffix(table: .posts, key: filter))"
        _ = provider.watchSocialEntityChanges(table: .posts, filter: filter, accessToken: nil, debugOwner: "Feed")
        _ = provider.watchNotifications(userID: "viewer-1", accessToken: nil, debugOwner: "Activity")
        await waitForConsumers(on: provider, routeKey: entityRoute, count: 1)

        let beforeGen = provider.testing_sessionGeneration()
        await provider.disconnect()
        await settleRegistration()

        XCTAssertGreaterThan(provider.testing_sessionGeneration(), beforeGen)
        XCTAssertEqual(provider.testing_routeSnapshot(routeKey: entityRoute).activeRouteCount, 0)
        XCTAssertEqual(provider.testing_routeSnapshot(routeKey: "notifications:viewer-1").consumerCount, 0)
    }

    func testSessionGenerationInvalidatesStaleConsumers() async {
        let provider = makeProvider()
        let routeKey = "viewer-profile:viewer-z"
        let watch = provider.watchViewerProfile(
            userID: "viewer-z",
            accessToken: nil,
            debugOwner: "BeforeLogout"
        )
        await settleRegistration()
        let generationBefore = provider.testing_sessionGeneration()

        await provider.disconnect()
        await settleRegistration()

        let watchAfter = provider.watchViewerProfile(
            userID: "viewer-z",
            accessToken: nil,
            debugOwner: "AfterLogin"
        )
        await settleRegistration()
        XCTAssertGreaterThan(provider.testing_sessionGeneration(), generationBefore)

        provider.testing_injectMessageSignal(
            routeKey: routeKey,
            signal: MessageRealtimeSignal(kind: .update, messageID: "viewer-z")
        )

        let received = expectation(description: "new session consumer receives")
        let drain = Task {
            for await _ in watchAfter.events {
                received.fulfill()
                break
            }
        }
        await fulfillment(of: [received], timeout: 2.0)
        drain.cancel()
        _ = watch
    }

    func testRepeatedStartStopDoesNotLeakConsumers() async {
        let provider = makeProvider()
        let filter = "user_id=eq.cycle-test-author"
        let routeKey = "social-entity:\(SocialEntityRealtimeTable.stableRouteSuffix(table: .posts, key: filter))"

        for index in 0 ..< 4 {
            let watch = provider.watchSocialEntityChanges(
                table: .posts,
                filter: filter,
                accessToken: nil,
                debugOwner: "Cycle\(index)"
            )
            await waitForConsumers(on: provider, routeKey: routeKey, count: 1)
            await provider.releaseWatch(watch.consumer)
            await waitForConsumers(on: provider, routeKey: routeKey, count: 0)
        }

        let snapshot = provider.testing_routeSnapshot(routeKey: routeKey)
        XCTAssertEqual(snapshot.consumerCount, 0)
        XCTAssertFalse(snapshot.isJoined)
    }

    func testRegistryAndTransportJoinLeaveCountsMatch() async {
        let provider = makeProvider()
        provider.testing_resetRegistryLifecycleCounters()
        let filter = "user_id=eq.transport-count-author"
        let routeKey = "social-entity:\(SocialEntityRealtimeTable.stableRouteSuffix(table: .posts, key: filter))"

        let watch = provider.watchSocialEntityChanges(
            table: .posts,
            filter: filter,
            accessToken: nil,
            debugOwner: "Transport"
        )
        await waitForConsumers(on: provider, routeKey: routeKey, count: 1)
        XCTAssertEqual(provider.testing_registryJoinCount(), 1)
        XCTAssertGreaterThanOrEqual(provider.testing_transportJoinCount(), 1)

        await provider.releaseWatch(watch.consumer)
        await waitForConsumers(on: provider, routeKey: routeKey, count: 0)
        XCTAssertEqual(provider.testing_registryLeaveCount(), 1)
        XCTAssertGreaterThanOrEqual(provider.testing_transportLeaveCount(), 1)
    }

    func testStaleRegistryJoinAttemptDoesNotDuplicateJoin() async {
        let provider = makeProvider()
        provider.testing_resetRegistryLifecycleCounters()
        let filter = "user_id=eq.stale-join-author"
        let routeKey = "social-entity:\(SocialEntityRealtimeTable.stableRouteSuffix(table: .posts, key: filter))"

        let watch = provider.watchSocialEntityChanges(
            table: .posts,
            filter: filter,
            accessToken: nil,
            debugOwner: "Stale"
        )
        await waitForConsumers(on: provider, routeKey: routeKey, count: 1)
        let transportBefore = provider.testing_transportJoinCount()
        await provider.testing_simulateStaleRegistryJoinAttempt(watch.consumer)
        XCTAssertEqual(provider.testing_registryJoinCount(), 1)
        XCTAssertEqual(provider.testing_transportJoinCount(), transportBefore)
    }

    func testRapidReleaseAndRetainSameRouteOneJoinOneLeavePerCycle() async {
        let provider = makeProvider()
        provider.testing_resetRegistryLifecycleCounters()
        let filter = "user_id=eq.rapid-cycle-author"
        let routeKey = "social-entity:\(SocialEntityRealtimeTable.stableRouteSuffix(table: .posts, key: filter))"

        for _ in 0 ..< 3 {
            let watch = provider.watchSocialEntityChanges(
                table: .posts,
                filter: filter,
                accessToken: nil,
                debugOwner: "Cycle"
            )
            await waitForConsumers(on: provider, routeKey: routeKey, count: 1)
            await provider.releaseWatch(watch.consumer)
            await waitForConsumers(on: provider, routeKey: routeKey, count: 0)
        }
        XCTAssertEqual(provider.testing_registryJoinCount(), provider.testing_registryLeaveCount())
        XCTAssertGreaterThanOrEqual(provider.testing_registryJoinCount(), 3)
    }

    func testExplicitReleaseThenDuplicateReleaseIgnored() async {
        let provider = makeProvider()
        let filter = "user_id=eq.explicit-dup-release"
        let routeKey = "social-entity:\(SocialEntityRealtimeTable.stableRouteSuffix(table: .posts, key: filter))"

        let watch = provider.watchSocialEntityChanges(
            table: .posts,
            filter: filter,
            accessToken: nil,
            debugOwner: "Once"
        )
        await waitForConsumers(on: provider, routeKey: routeKey, count: 1)
        await provider.releaseWatch(watch.consumer)
        provider.testing_resetRegistryLifecycleCounters()
        await provider.releaseWatch(watch.consumer)
        await provider.releaseWatch(watch.consumer)
        XCTAssertEqual(provider.testing_registryLeaveCount(), 0)
        XCTAssertEqual(provider.testing_transportLeaveCount(), 0)
        XCTAssertEqual(provider.testing_routeSnapshot(routeKey: routeKey).consumerCount, 0)
    }
}
