import Foundation
import Observation

extension Notification.Name {
    static let contextualTourDidComplete = Notification.Name("contextualTourDidComplete")
    static let postOnboardingPlanSelectionDidDismiss = Notification.Name("postOnboardingPlanSelectionDidDismiss")
}

/// Presents the one-time TraxsPro vs Free sheet after the contextual walkthrough settles (or on next launch when the tour already settled).
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
        pendingUserID = userID
        lastAccountCreatedAt = accountCreatedAt
        reevaluatePresentation()
    }

    func handleTourCompleted(userID: String?) {
        guard let userID, userID == pendingUserID else { return }
        reevaluatePresentation(forceAfterTour: true)
    }

    func handleShellGatesChanged(
        tourPhase: ContextualTourPhase,
        tourOverlayVisible: Bool,
        blockingModalPresented: Bool
    ) {
        guard tourPhase == .idle, !tourOverlayVisible, !blockingModalPresented else {
            if isPresented, tourOverlayVisible || tourPhase != .idle {
                isPresented = false
            }
            return
        }
        reevaluatePresentation()
    }

    func markCompletedAndDismiss() {
        if let userID = pendingUserID {
            progress.markCompleted(userID: userID)
        }
        isPresented = false
        NotificationCenter.default.post(name: .postOnboardingPlanSelectionDidDismiss, object: nil)
    }

    /// Defers contextual-tour follow-up navigation (e.g. Trading Rules) until after the plan chooser.
    func defersPostTourNavigation(userID: String?) -> Bool {
        guard let userID, !userID.isEmpty else { return false }
        return !progress.hasCompleted(userID: userID)
    }

    private func reevaluatePresentation(forceAfterTour: Bool = false) {
        guard let userID = pendingUserID, !userID.isEmpty else {
            isPresented = false
            return
        }
        guard !progress.hasCompleted(userID: userID) else {
            isPresented = false
            return
        }

        let tourSettled = walkthroughSettled(for: userID, forceAfterTour: forceAfterTour)
        let tour = ContextualTourCoordinator.shared
        guard tourSettled, tour.phase == .idle, !tour.showsOverlay else {
            return
        }

        isPresented = true
    }

  private func walkthroughSettled(for userID: String, forceAfterTour: Bool) -> Bool {
        if forceAfterTour { return true }
        let tourEligible = ContextualTourEligibility.isAccountEligible(
            createdAt: lastAccountCreatedAt,
            cutoff: ContextualTourLaunch.accountCreatedAtCutoff
        )
        if !tourEligible {
            return true
        }
        let dismissed = ContextualTourProgressStore().dismissedVersion(for: .dashboard, userID: userID)
        return dismissed >= ContextualTourCatalog.dashboard.version
    }
}