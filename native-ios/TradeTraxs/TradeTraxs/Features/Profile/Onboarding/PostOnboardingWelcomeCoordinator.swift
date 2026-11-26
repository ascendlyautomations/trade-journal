import Foundation
import Observation

extension Notification.Name {
    static let postOnboardingWelcomeDidDismiss = Notification.Name("postOnboardingWelcomeDidDismiss")
}

/// Presents the one-time welcome modal before the optional App Walkthrough.
@MainActor
@Observable
final class PostOnboardingWelcomeCoordinator {
    static let shared = PostOnboardingWelcomeCoordinator()

    var isPresented = false
    private var pendingUserID: String?
    private var didPrepareDashboard = false

    private init() {}

    func noteAccountContext(userID: String?) {
        pendingUserID = userID
        reevaluatePresentation()
    }

    func handleShellGatesChanged(
        tourPhase: ContextualTourPhase,
        tourOverlayVisible: Bool,
        blockingModalPresented: Bool
    ) {
        guard tourPhase == .idle, !tourOverlayVisible else {
            if isPresented, tourOverlayVisible || tourPhase != .idle {
                isPresented = false
            }
            return
        }
        reevaluatePresentation(blockingModalPresented: blockingModalPresented)
    }

    func prepareDashboardIfNeeded(navigationCoordinator: NavigationCoordinator) {
        guard !didPrepareDashboard else { return }
        didPrepareDashboard = true
        navigationCoordinator.selectTab(.home)
        navigationCoordinator.popToRoot(.home)
    }

    func resetDashboardPreparation() {
        didPrepareDashboard = false
    }

    func takeTour(navigationCoordinator: NavigationCoordinator) {
        guard let userID = pendingUserID, !userID.isEmpty else {
            isPresented = false
            return
        }
        let profileID = ProfileID(userID)
        PostAuthOnboardingWelcomeStore.record(profileID: profileID, choice: .tour)
        isPresented = false
        NotificationCenter.default.post(name: .postOnboardingWelcomeDidDismiss, object: nil)
        prepareDashboardIfNeeded(navigationCoordinator: navigationCoordinator)
        ContextualTourCoordinator.shared.notePostOnboardingWalkthroughShouldPresent(userID: userID)
    }

    func maybeLater() {
        guard let userID = pendingUserID, !userID.isEmpty else {
            isPresented = false
            return
        }
        let profileID = ProfileID(userID)
        PostAuthOnboardingWelcomeStore.record(profileID: profileID, choice: .later)
        let tourVersion = ContextualTourCatalog.dashboard.version
        ContextualTourProgressStore().dismiss(.dashboard, version: tourVersion, userID: userID)
        NativeIosOnboardingSync.recordTourDismissed(
            userID: userID,
            version: tourVersion,
            rpc: NativeIosOnboardingServices.rpc
        )
        PostAuthOnboardingProgress.markWalkthroughFinished(for: profileID)
        isPresented = false
        NotificationCenter.default.post(name: .postOnboardingWelcomeDidDismiss, object: nil)
    }

    func presentAfterPlanIfNeeded(userID: String) {
        pendingUserID = userID
        let profileID = ProfileID(userID)
        guard PostAuthOnboardingPolicy.shouldPresentWelcomeModal(profileID: profileID) else {
            if PostAuthOnboardingPolicy.shouldArmWalkthroughAfterPlan(profileID: profileID) {
                ContextualTourCoordinator.shared.notePostOnboardingWalkthroughShouldPresent(userID: userID)
            } else {
                PostAuthOnboardingProgress.markWalkthroughFinished(for: profileID)
            }
            return
        }
        didPrepareDashboard = false
        isPresented = true
    }

    func resetForSessionBoundary() {
        isPresented = false
        pendingUserID = nil
        didPrepareDashboard = false
    }

    func reevaluatePresentation(blockingModalPresented: Bool = false) {
        guard let userID = pendingUserID, !userID.isEmpty else {
            isPresented = false
            return
        }
        let profileID = ProfileID(userID)
        guard PostAuthOnboardingPolicy.shouldPresentWelcomeModal(profileID: profileID) else {
            isPresented = false
            return
        }

        let tour = ContextualTourCoordinator.shared
        guard !tour.showsOverlay, tour.phase == .idle else {
            if isPresented {
                isPresented = false
            }
            return
        }

        guard !blockingModalPresented else { return }

        isPresented = true
    }
}