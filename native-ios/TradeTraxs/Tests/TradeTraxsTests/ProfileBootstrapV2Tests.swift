import XCTest
@testable import TradeTraxs

@MainActor
final class ProfileBootstrapV2Tests: XCTestCase {
    func testDevelopmentBootstrapFillsAllSectionsOnce() async {
        let environment = CompositionRoot.bootstrap()
        let state = await ProfileBootstrap.load(
            .init(
                target: .profile(ProfileID("dev.bootstrap-v2")),
                profiles: environment.data.profiles,
                trades: environment.data.trades,
                achievements: environment.data.achievements,
                feed: environment.data.feed,
                rooms: environment.data.rooms,
                session: environment.data.session,
                detailCache: environment.data.detailCache,
                force: false
            )
        )

        XCTAssertTrue(state.didBootstrap)
        XCTAssertEqual(state.phase, .loaded)
        XCTAssertNotNil(state.profile)
        XCTAssertNotNil(state.stats)
        XCTAssertFalse(state.trades.isEmpty)
        XCTAssertFalse(state.posts.isEmpty)
        XCTAssertFalse(state.achievements.isEmpty)
        XCTAssertNotNil(state.payoutTotal)
    }

    func testScreenViewModelBootstrapAppliesToSectionViewModelsWithoutAutonomousLoad() async {
        let environment = CompositionRoot.bootstrap()
        let screen = ProfileScreenViewModel(
            target: .profile(ProfileID("dev.bootstrap-screen")),
            currentUserProfile: environment.currentUserProfile,
            navigationCoordinator: environment.navigation.coordinator,
            authenticationCoordinator: nil,
            data: environment.data,
            showsOwnerChrome: false
        )

        screen.onAppear(currentUserProfile: environment.currentUserProfile)

        let deadline = Date().addingTimeInterval(3)
        while !screen.state.didBootstrap, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertTrue(screen.state.didBootstrap)
        XCTAssertEqual(screen.contentStore.phase, .loaded)
        XCTAssertTrue(screen.contentStore.isScreenOwned)

        screen.syncShellIfNeeded()
        screen.activateShellForLaunch()

        guard let trades = screen.shellViewModel?.trades else {
            return XCTFail("Expected trades section after bootstrap")
        }
        XCTAssertEqual(trades.items.count, screen.state.trades.count)
        XCTAssertNotEqual(trades.state, .idle)

        screen.shellViewModel?.select(.stats)
        guard let stats = screen.shellViewModel?.stats else {
            return XCTFail("Expected stats section")
        }
        XCTAssertNotNil(stats.metrics)
        XCTAssertEqual(stats.payoutTotal, screen.state.payoutTotal)

        screen.shellViewModel?.select(.achievements)
        XCTAssertEqual(
            screen.shellViewModel?.achievements?.items.count,
            screen.state.achievements.count
        )

        screen.shellViewModel?.select(.posts)
        XCTAssertEqual(screen.shellViewModel?.posts?.items.count, screen.state.posts.count)
    }

    func testSectionLoadIfNeededIsNoOpAfterBootstrapApply() async {
        let environment = CompositionRoot.bootstrap()
        let profileID = ProfileID("dev.bootstrap-noop")
        let snapshot = await ProfileBootstrap.load(
            .init(
                target: .profile(profileID),
                profiles: environment.data.profiles,
                trades: environment.data.trades,
                achievements: environment.data.achievements,
                feed: environment.data.feed,
                rooms: environment.data.rooms,
                session: environment.data.session,
                detailCache: environment.data.detailCache,
                force: false
            )
        )

        let trades = TradesContainerViewModel(
            profileID: profileID,
            trades: environment.data.trades,
            navigationCoordinator: environment.navigation.coordinator,
            detailCache: environment.data.detailCache
        )
        trades.applyBootstrap(snapshot)
        let count = trades.items.count
        trades.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(trades.items.count, count)
    }
}
