import XCTest
@testable import TradeTraxs

@MainActor
final class GuestSessionEntryTests: XCTestCase {
    private var savedIssuer: (@Sendable (AppConfiguration) async -> GuestSessionIssuance?)?

    override func setUp() async throws {
        savedIssuer = GuestSessionClient.issuer
        let launch = AppLaunchController.shared
        if launch.isDemoExperienceActive {
            launch.exitDemoExplore()
        }
        launch.dismissGuestExploreFailure()
        launch.environment.authentication.manager.sessionManagerForNetworking.clearMemory()
    }

    override func tearDown() async throws {
        if let savedIssuer {
            GuestSessionClient.issuer = savedIssuer
        }
        let launch = AppLaunchController.shared
        launch.dismissGuestExploreFailure()
        if launch.isDemoExperienceActive {
            launch.exitDemoExplore()
        }
        _ = try? launch.environment.authentication.manager.sessionManagerForNetworking.restoreFromStore()
    }

    func testRealSignInReplacesGuestBearerForAuthenticatedTransport() async throws {
        let launch = AppLaunchController.shared
        let manager = launch.environment.authentication.manager
        let showcaseID = GuestShowcaseAccount.productionUserID
        let realUserID = UserID("de0ad507-1111-4111-8111-111111111111")
        let guest = GuestSessionIssuance(
            userID: showcaseID,
            accessToken: "guest.access.token",
            expiresAt: Date().addingTimeInterval(-30)
        )
        let real = AuthenticationSession(
            userID: realUserID,
            email: "owner@tradetraxs.test",
            accessToken: "real.access.token",
            refreshToken: "real.refresh.token",
            expiresAt: Date().addingTimeInterval(3_600),
            provider: .email,
            createdAt: Date(),
            lastRefreshedAt: nil
        )

        await launch.installGuestSessionForTesting(guest)
        XCTAssertEqual(manager.sessionManagerForNetworking.accessToken, guest.accessToken)
        XCTAssertTrue(launch.guestSessionIsInstalled)
        XCTAssertNil(manager.sessionManagerForNetworking.currentSession?.refreshToken)

        launch.relinquishGuestSessionForAuthenticatedSignIn()
        manager.sessionManagerForNetworking.installEphemeral(real)

        let bearer = manager.sessionManagerForNetworking.accessToken
        XCTAssertEqual(bearer, real.accessToken)
        XCTAssertEqual(manager.sessionManagerForNetworking.currentSession?.userID, realUserID)
        XCTAssertEqual(manager.sessionManagerForNetworking.currentSession?.refreshToken, real.refreshToken)
        XCTAssertNotEqual(bearer, guest.accessToken)
        XCTAssertFalse(launch.guestSessionIsInstalled)
        XCTAssertFalse(launch.isDemoExperienceActive)

        await launch.installGuestSessionForTesting(guest)
        XCTAssertEqual(manager.sessionManagerForNetworking.accessToken, real.accessToken)
        XCTAssertFalse(launch.guestSessionIsInstalled)
    }

    func testGuestInstallSurvivesPriorSessionEndAndExitCancelsIt() async throws {
        let launch = AppLaunchController.shared
        let coordinator = NetworkConcurrencyCoordinator.shared
        let priorEnd = AuthLifecycleGeneration.bump()
        _ = await coordinator.resetForAuthenticatedSessionEnd(authGeneration: priorEnd)

        let guest = GuestSessionIssuance(
            userID: GuestShowcaseAccount.productionUserID,
            accessToken: "guest.access.token",
            expiresAt: Date().addingTimeInterval(3_600)
        )
        await launch.installGuestSessionForTesting(guest)
        let installedGeneration = AuthLifecycleGeneration.current()

        let feed = try await coordinator.runWithSlot(
            priority: .visible,
            path: "/rest/v1/rpc/rpc_v1_feed_bootstrap",
            host: "test",
            method: .post
        ) { "feed" }
        let messages = try await coordinator.runWithSlot(
            priority: .visible,
            path: "/rest/v1/rpc/rpc_v2_messaging_bootstrap",
            host: "test",
            method: .post
        ) { "messages" }
        let profile = try await coordinator.runWithSlot(
            priority: .visible,
            path: "/rest/v1/rpc/rpc_v1_profile_bootstrap",
            host: "test",
            method: .post
        ) { "profile" }
        XCTAssertEqual(feed, "feed")
        XCTAssertEqual(messages, "messages")
        XCTAssertEqual(profile, "profile")
        let activeGeneration = await coordinator.currentSessionEndGeneration()
        XCTAssertEqual(activeGeneration, installedGeneration)

        let staleEnd = priorEnd
        _ = await coordinator.resetForAuthenticatedSessionEnd(authGeneration: staleEnd)
        let stillFeed = try await coordinator.runWithSlot(
            priority: .visible,
            path: "/rest/v1/rpc/rpc_v1_feed_bootstrap",
            host: "test",
            method: .post
        ) { "feed-still" }
        XCTAssertEqual(stillFeed, "feed-still")

        launch.exitDemoExplore()
        await launch.awaitGuestNetworkBoundaryForTesting()

        do {
            _ = try await coordinator.runWithSlot(
                priority: .visible,
                path: "/rest/v1/rpc/rpc_v1_feed_bootstrap",
                host: "test",
                method: .post
            ) { "cancelled" }
            XCTFail("Guest exit should cancel authenticated acquires")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected cancellation, got \(error)")
        }

        let signedIn = AuthLifecycleGeneration.bump()
        await coordinator.markAuthenticatedSessionActive(authGeneration: signedIn)
        let restored = try await coordinator.runWithSlot(
            priority: .visible,
            path: "/rest/v1/rpc/rpc_v1_profile_bootstrap",
            host: "test",
            method: .post
        ) { "signed-in" }
        XCTAssertEqual(restored, "signed-in")
        XCTAssertGreaterThan(signedIn, installedGeneration)
    }

    func testGuestExitKeepsProductionBootstrapForRealSignIn() async throws {
        let launch = AppLaunchController.shared
        guard launch.deferredProductionBootstrapAvailable else {
            throw XCTSkip("Production bootstrap was already consumed in this process")
        }
        let showcaseID = GuestShowcaseAccount.productionUserID
        GuestSessionClient.issuer = { _ in
            GuestSessionIssuance(
                userID: showcaseID,
                accessToken: "guest.bootstrap.token",
                expiresAt: Date().addingTimeInterval(3_600)
            )
        }
        launch.enterGuestExploreBypassingAuthGateForTesting()
        for _ in 0..<200 where !launch.isDemoExperienceActive && !launch.guestExploreFailurePresented {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(launch.isDemoExperienceActive)
        XCTAssertTrue(launch.deferredProductionBootstrapAvailable)
        XCTAssertEqual(
            launch.environment.authentication.manager.sessionManagerForNetworking.accessToken,
            "guest.bootstrap.token"
        )

        launch.exitDemoExplore()
        XCTAssertFalse(launch.isDemoExperienceActive)
        XCTAssertFalse(launch.guestSessionIsInstalled)
        XCTAssertNil(launch.environment.authentication.manager.sessionManagerForNetworking.accessToken)
        XCTAssertTrue(launch.deferredProductionBootstrapAvailable)
        XCTAssertTrue(launch.environment.isDeferredBootstrapPending)

        await launch.ensureFullBootstrapComplete()
        let real = AuthenticationSession(
            userID: UserID("de0ad507-1111-4111-8111-111111111111"),
            email: "owner@tradetraxs.test",
            accessToken: "real.access.token",
            refreshToken: "real.refresh.token",
            expiresAt: Date().addingTimeInterval(3_600),
            provider: .email,
            createdAt: Date(),
            lastRefreshedAt: nil
        )
        launch.relinquishGuestSessionForAuthenticatedSignIn()
        launch.environment.authentication.manager.sessionManagerForNetworking.installEphemeral(real)

        XCTAssertFalse(launch.deferredProductionBootstrapAvailable)
        XCTAssertFalse(launch.environment.isDeferredBootstrapPending)
        XCTAssertEqual(
            launch.environment.authentication.manager.sessionManagerForNetworking.accessToken,
            "real.access.token"
        )
        XCTAssertFalse(launch.guestSessionIsInstalled)
    }

    func testGuestSessionFailureStaysSignedOut() async throws {
        GuestSessionClient.issuer = { _ in nil }
        let launch = AppLaunchController.shared
        let event = launch.environment.authentication.manager.lastEvent

        launch.enterGuestExploreBypassingAuthGateForTesting()
        for _ in 0..<40 where !launch.guestExploreFailurePresented {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertTrue(launch.guestExploreFailurePresented)
        XCTAssertEqual(
            AppLaunchController.guestExploreFailureMessage,
            "Unable to load Explore as Guest. Please try again."
        )
        XCTAssertFalse(launch.isDemoExperienceActive)
        XCTAssertFalse(launch.guestSessionIsInstalled)
        XCTAssertFalse(DemoExperienceSupport.skipsAuthenticatedViewerServices)
        XCTAssertFalse(DemoExperienceSupport.usesExploreDemoInbox(DemoExperienceSupport.profileID))
        XCTAssertEqual(launch.environment.authentication.manager.lastEvent, event)
    }

    func testExpiredGuestTokenReissuesWithoutGoTrueRefresh() async throws {
        let launch = AppLaunchController.shared
        let manager = launch.environment.authentication.manager
        let event = manager.lastEvent
        let wasReady = manager.state.isSessionReady
        let counter = IssueCounter()
        GuestSessionClient.issuer = { _ in
            await counter.increment()
            return GuestSessionIssuance(
                userID: GuestShowcaseAccount.productionUserID,
                accessToken: "guest.renewed",
                expiresAt: Date().addingTimeInterval(3_600)
            )
        }
        await launch.installGuestSessionForTesting(
            GuestSessionIssuance(
                userID: GuestShowcaseAccount.productionUserID,
                accessToken: "guest.expired",
                expiresAt: Date().addingTimeInterval(-30)
            )
        )

        let renewed = await launch.renewExpiredGuestSession()

        XCTAssertTrue(renewed)
        let issues = await counter.value
        XCTAssertEqual(issues, 1)
        let session = manager.sessionManagerForNetworking.currentSession
        XCTAssertEqual(session?.accessToken, "guest.renewed")
        XCTAssertNil(session?.refreshToken)
        XCTAssertEqual(session?.userID.rawValue, GuestShowcaseAccount.productionUserIDRaw)
        XCTAssertTrue(launch.isDemoExperienceActive)
        XCTAssertTrue(launch.guestSessionIsInstalled)
        XCTAssertFalse(launch.guestExploreFailurePresented)
        XCTAssertFalse(DemoExperienceSupport.skipsAuthenticatedViewerServices)
        XCTAssertEqual(manager.lastEvent, event)
        XCTAssertEqual(manager.state.isSessionReady, wasReady)
    }

    func testExpiredGuestReissueFailureReturnsToSignIn() async throws {
        GuestSessionClient.issuer = { _ in nil }
        let launch = AppLaunchController.shared
        let event = launch.environment.authentication.manager.lastEvent
        await launch.installGuestSessionForTesting(
            GuestSessionIssuance(
                userID: GuestShowcaseAccount.productionUserID,
                accessToken: "guest.expired",
                expiresAt: Date().addingTimeInterval(-30)
            )
        )

        let renewed = await launch.renewExpiredGuestSession()

        XCTAssertFalse(renewed)
        XCTAssertFalse(launch.isDemoExperienceActive)
        XCTAssertFalse(launch.guestSessionIsInstalled)
        XCTAssertTrue(launch.guestExploreFailurePresented)
        XCTAssertNil(launch.environment.authentication.manager.sessionManagerForNetworking.currentSession)
        XCTAssertEqual(launch.environment.authentication.manager.lastEvent, event)
        XCTAssertFalse(DemoExperienceSupport.usesLocalBundledData(GuestShowcaseAccount.productionProfileID))
    }

    func testConcurrentGuestReissueUsesOneRequest() async throws {
        let launch = AppLaunchController.shared
        let counter = IssueCounter()
        GuestSessionClient.issuer = { _ in
            await counter.increment()
            try? await Task.sleep(nanoseconds: 150_000_000)
            return GuestSessionIssuance(
                userID: GuestShowcaseAccount.productionUserID,
                accessToken: "guest.once",
                expiresAt: Date().addingTimeInterval(3_600)
            )
        }
        await launch.installGuestSessionForTesting(
            GuestSessionIssuance(
                userID: GuestShowcaseAccount.productionUserID,
                accessToken: "guest.expired",
                expiresAt: Date().addingTimeInterval(-5)
            )
        )

        async let first = launch.renewExpiredGuestSession()
        async let second = launch.renewExpiredGuestSession()
        let results = await (first, second)

        XCTAssertTrue(results.0)
        XCTAssertTrue(results.1)
        let issues = await counter.value
        XCTAssertEqual(issues, 1)
        XCTAssertEqual(
            launch.environment.authentication.manager.sessionManagerForNetworking.currentSession?.accessToken,
            "guest.once"
        )
        XCTAssertNil(
            launch.environment.authentication.manager.sessionManagerForNetworking.currentSession?.refreshToken
        )
    }

}

private actor IssueCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    var value: Int { count }
}
