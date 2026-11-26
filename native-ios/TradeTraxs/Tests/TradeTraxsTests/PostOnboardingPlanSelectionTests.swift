import XCTest
@testable import TradeTraxs

@MainActor
final class PostOnboardingPlanSelectionTests: XCTestCase {
    private var userID = ""
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        userID = UUID().uuidString
        suiteName = "PostOnboardingPlanSelectionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        PostOnboardingPlanSelectionProgressStore().clear(userID: userID)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testCompletionPersistenceIsPerAccount() {
        let store = PostOnboardingPlanSelectionProgressStore(defaults: defaults)
        XCTAssertFalse(store.hasCompleted(userID: userID))
        store.markCompleted(userID: userID)
        XCTAssertTrue(store.hasCompleted(userID: userID))
    }

    func testDefersTradingRulesUntilChooserCompletes() {
        let coordinator = PostOnboardingPlanSelectionCoordinator.shared
        XCTAssertTrue(coordinator.defersPostTourNavigation(userID: userID))
        coordinator.noteAccountContext(userID: userID, accountCreatedAt: Date())
        coordinator.markCompletedAndDismiss()
        XCTAssertFalse(coordinator.defersPostTourNavigation(userID: userID))
    }

    func testWebCompleteUserDoesNotSeeMainShellPlanSheet() {
        let coordinator = PostOnboardingPlanSelectionCoordinator.shared
        NativeIosOnboardingSessionStore.apply(
            session: SessionProfileV1(
                id: userID,
                onboarding_completed: true
            )
        )
        coordinator.noteAccountContext(userID: userID, accountCreatedAt: Date())
        coordinator.reevaluatePresentation(blockingModalPresented: false)
        XCTAssertFalse(coordinator.isPresented)
    }
}