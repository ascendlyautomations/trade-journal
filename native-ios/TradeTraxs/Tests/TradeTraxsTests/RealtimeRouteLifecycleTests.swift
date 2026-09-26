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

    private func watchNotifications(
        provider: LiveSupabaseRealtimeProvider,
        userID: String,
        owner: String
    ) -> RealtimeMessageWatch {
        provider.watchNotifications(userID: userID, accessToken: nil, debugOwner: owner)
    }

    func testTwoConsumersShareOneRouteUntilFinalRelease() async {
        let provider = makeProvider()
        let userID = "shared-route-viewer"
        let routeKey = "notifications:\(userID)"

        let watchA = watchNotifications(provider: provider, userID: userID, owner: "ActivityA")
        await waitForConsumers(on: provider, routeKey: routeKey, count: 1)
        let watchB = watchNotifications(provider: provider, userID: userID, owner: "ActivityB")
        await waitForConsumers(on: provider, routeKey: routeKey, count: 2)

        let both = provider.testing_routeSnapshot(routeKey: routeKey)
        XCTAssertEqual(both.consumerCount, 2)
        XCTAssertTrue(both.isJoined)

        await provider.releaseWatch(watchA.consumer)
        await waitForConsumers(on: provider, routeKey: routeKey, count: 1)

        let afterA = provider.testing_routeSnapshot(routeKey: routeKey)
        XCTAssertEqual(afterA.consumerCount, 1)
        XCTAssertTrue(afterA.isJoined)

        let signal = MessageRealtimeSignal(kind: .insert, messageID: "n-1")
        let received = expectation(description: "consumer B receives event")
        let drain = Task {
            for await _ in watchB.events {
                received.fulfill()
                break
            }
        }
        provider.testing_injectMessageSignal(routeKey: routeKey, signal: signal)
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
        let userID = "lifecycle-test-viewer"
        let routeKey = "notifications:\(userID)"

        let watchA = watchNotifications(provider: provider, userID: userID, owner: "A")
        await waitForConsumers(on: provider, routeKey: routeKey, count: 1)
        let watchB = watchNotifications(provider: provider, userID: userID, owner: "B")
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

    func testDuplicateReleaseSameHandleIsNoOp() async {
        let provider = makeProvider()
        provider.testing_resetRegistryLifecycleCounters()
        let userID = "duplicate-release-viewer"
        let routeKey = "notifications:\(userID)"

        let watch = watchNotifications(provider: provider, userID: userID, owner: "Once")
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
        let userID = "two-consumer-viewer"
        let routeKey = "notifications:\(userID)"

        let watchA = watchNotifications(provider: provider, userID: userID, owner: "A")
        await waitForConsumers(on: provider, routeKey: routeKey, count: 1)
        XCTAssertEqual(provider.testing_registryJoinCount(), 1)

        let watchB = watchNotifications(provider: provider, userID: userID, owner: "B")
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
        let userID = "disconnect-test-viewer"
        let routeKey = "notifications:\(userID)"
        _ = watchNotifications(provider: provider, userID: userID, owner: "Activity")
        await waitForConsumers(on: provider, routeKey: routeKey, count: 1)

        let beforeGen = provider.testing_sessionGeneration()
        await provider.disconnect()
        await settleRegistration()

        XCTAssertGreaterThan(provider.testing_sessionGeneration(), beforeGen)
        XCTAssertEqual(provider.testing_routeSnapshot(routeKey: routeKey).activeRouteCount, 0)
        XCTAssertEqual(provider.testing_routeSnapshot(routeKey: routeKey).consumerCount, 0)
    }

    func testSessionGenerationInvalidatesStaleConsumers() async {
        let provider = makeProvider()
        let userID = "session-gen-viewer"
        let routeKey = "notifications:\(userID)"
        let watch = watchNotifications(provider: provider, userID: userID, owner: "BeforeLogout")
        await settleRegistration()
        let generationBefore = provider.testing_sessionGeneration()

        await provider.disconnect()
        await settleRegistration()

        let watchAfter = watchNotifications(provider: provider, userID: userID, owner: "AfterLogin")
        await settleRegistration()
        XCTAssertGreaterThan(provider.testing_sessionGeneration(), generationBefore)

        provider.testing_injectMessageSignal(
            routeKey: routeKey,
            signal: MessageRealtimeSignal(kind: .insert, messageID: "n-after")
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
        let userID = "cycle-test-viewer"
        let routeKey = "notifications:\(userID)"

        for index in 0 ..< 4 {
            let watch = watchNotifications(provider: provider, userID: userID, owner: "Cycle\(index)")
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
        let userID = "transport-count-viewer"
        let routeKey = "notifications:\(userID)"

        let watch = watchNotifications(provider: provider, userID: userID, owner: "Transport")
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
        let userID = "stale-join-viewer"
        let routeKey = "notifications:\(userID)"

        let watch = watchNotifications(provider: provider, userID: userID, owner: "Stale")
        await waitForConsumers(on: provider, routeKey: routeKey, count: 1)
        let transportBefore = provider.testing_transportJoinCount()
        await provider.testing_simulateStaleRegistryJoinAttempt(watch.consumer)
        XCTAssertEqual(provider.testing_registryJoinCount(), 1)
        XCTAssertEqual(provider.testing_transportJoinCount(), transportBefore)
    }

    func testRapidReleaseAndRetainSameRouteOneJoinOneLeavePerCycle() async {
        let provider = makeProvider()
        provider.testing_resetRegistryLifecycleCounters()
        let userID = "rapid-cycle-viewer"
        let routeKey = "notifications:\(userID)"

        for _ in 0 ..< 3 {
            let watch = watchNotifications(provider: provider, userID: userID, owner: "Cycle")
            await waitForConsumers(on: provider, routeKey: routeKey, count: 1)
            await provider.releaseWatch(watch.consumer)
            await waitForConsumers(on: provider, routeKey: routeKey, count: 0)
        }
        XCTAssertEqual(provider.testing_registryJoinCount(), provider.testing_registryLeaveCount())
        XCTAssertGreaterThanOrEqual(provider.testing_registryJoinCount(), 3)
    }

    func testExplicitReleaseThenDuplicateReleaseIgnored() async {
        let provider = makeProvider()
        let userID = "explicit-dup-release"
        let routeKey = "notifications:\(userID)"

        let watch = watchNotifications(provider: provider, userID: userID, owner: "Once")
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
