import Foundation
import Observation

extension Notification.Name {
    static let contextualTourDidComplete = Notification.Name("contextualTourDidComplete")
    static let postOnboardingPlanSelectionDidDismiss = Notification.Name("postOnboardingPlanSelectionDidDismiss")
}

/// Presents the one-time TraxsPro vs Free chooser **before** the contextual walkthrough (native funnel only).
@MainActor
@Observable
final class PostOnboardingPlanSelectionCoordinator {
    static let shared = PostOnboardingPlanSelectionCoordinator()

    private let progress = PostOnboardingPlanSelectionProgressStore()
    var isPresented = false
    private var pendingUserID: String?
    private var lastAccountCreatedAt: Date?

    private init() {}

    func noteAccountContext(userID: String?, accountCreatedAt: Date?) {
        let createdAtChanged = lastAccountCreatedAt != accountCreatedAt
        pendingUserID = userID
        lastAccountCreatedAt = accountCreatedAt
        reevaluatePresentation()
        if createdAtChanged {
            ContextualTourCoordinator.shared.refreshAccountCreatedAt(accountCreatedAt)
        }
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

    func markCompletedAndDismiss() {
        if let userID = pendingUserID {
            progress.markCompleted(userID: userID)
            PostAuthOnboardingProgress.markPlanFinished(for: ProfileID(userID))
            NativeIosOnboardingSync.recordPlanAcknowledged(
                userID: userID,
                rpc: NativeIosOnboardingServices.rpc
            )
        }
        isPresented = false
        NotificationCenter.default.post(name: .postOnboardingPlanSelectionDidDismiss, object: nil)
        if let userID = pendingUserID {
            PostOnboardingWelcomeCoordinator.shared.presentAfterPlanIfNeeded(userID: userID)
        }
    }

    /// Defers contextual-tour follow-up navigation (e.g. Trading Rules) until after the plan chooser.
    func defersPostTourNavigation(userID: String?) -> Bool {
        guard let userID, !userID.isEmpty else { return false }
        return !PostAuthOnboardingPolicy.hasSatisfiedNativePlanStep(userID: userID)
    }

    func reevaluatePresentation(blockingModalPresented: Bool = false) {
        guard let userID = pendingUserID, !userID.isEmpty else {
            isPresented = false
            return
        }
        guard PostAuthOnboardingPolicy.shouldPresentPlanOnMainShell(userID: userID) else {
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

        guard !blockingModalPresented else {
            return
        }

        isPresented = true
    }
}