import XCTest
@testable import TradeTraxs

@MainActor
final class NativeIosOnboardingPolicyTests: XCTestCase {
    private var userID = ""

    override func setUp() {
        super.setUp()
        userID = UUID().uuidString
        NativeIosOnboardingSessionStore.reset()
        PostOnboardingPlanSelectionProgressStore().clear(userID: userID)
        ContextualTourProgressStore().clearDismissals(userID: userID)
        PostAuthOnboardingProgress.clear(for: ProfileID(userID))
    }

    func testWebCompleteSkipsPlanAndArmsWalkthrough() {
        NativeIosOnboardingSessionStore.apply(
            session: SessionProfileV1(
                id: userID,
                onboarding_completed: true,
                ios_contextual_tour_dismissed_version: 0,
                ios_post_onboarding_plan_acknowledged: false
            )
        )
        let profileID = ProfileID(userID)
        XCTAssertFalse(PostAuthOnboardingPolicy.shouldPresentPlanOnMainShell(userID: userID))
        XCTAssertFalse(
            PostAuthOnboardingPolicy.shouldPresentPlanSelection(
                profileID: profileID,
                accountCreatedAt: nil
            )
        )
        XCTAssertTrue(PostAuthOnboardingPolicy.shouldPresentAutomaticWalkthrough(profileID: profileID))
    }

    func testDismissedTourDoesNotAutoPresent() {
        NativeIosOnboardingSessionStore.apply(
            session: SessionProfileV1(
                id: userID,
                onboarding_completed: true,
                ios_contextual_tour_dismissed_version: ContextualTourCatalog.dashboard.version,
                ios_post_onboarding_plan_acknowledged: false
            )
        )
        XCTAssertFalse(
            PostAuthOnboardingPolicy.shouldPresentAutomaticWalkthrough(profileID: ProfileID(userID))
        )
    }

    func testEffectiveDismissalUsesMaxOfLocalAndServer() {
        ContextualTourProgressStore().dismiss(
            .dashboard,
            version: 1,
            userID: userID
        )
        NativeIosOnboardingSessionStore.apply(
            session: SessionProfileV1(
                id: userID,
                onboarding_completed: true,
                ios_contextual_tour_dismissed_version: 0
            )
        )
        XCTAssertEqual(PostAuthOnboardingPolicy.effectiveTourDismissedVersion(userID: userID), 1)
    }
}