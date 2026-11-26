import Foundation

/// Local resume state for post-profile onboarding: broker → plan → walkthrough → finished.
enum PostAuthOnboardingProgress {
    enum Step: String, Sendable {
        case broker
        case plan
        case walkthrough
        case finished
    }

    private static func stepKey(_ profileID: ProfileID) -> String {
        "tt.postAuthOnboarding.step.\(profileID.rawValue)"
    }

    static func activateFunnel(for profileID: ProfileID) {
        UserDefaults.standard.set(Step.broker.rawValue, forKey: stepKey(profileID))
    }

    static func currentStep(for profileID: ProfileID) -> Step? {
        guard let raw = UserDefaults.standard.string(forKey: stepKey(profileID)),
              let step = Step(rawValue: raw)
        else { return nil }
        return step
    }

    static func markBrokerFinished(for profileID: ProfileID) {
        UserDefaults.standard.set(Step.plan.rawValue, forKey: stepKey(profileID))
    }

    static func markPlanFinished(for profileID: ProfileID) {
        UserDefaults.standard.set(Step.walkthrough.rawValue, forKey: stepKey(profileID))
    }

    static func markWalkthroughFinished(for profileID: ProfileID) {
        UserDefaults.standard.set(Step.finished.rawValue, forKey: stepKey(profileID))
    }

    static func clear(for profileID: ProfileID) {
        UserDefaults.standard.removeObject(forKey: stepKey(profileID))
    }
}

/// One-time welcome modal before the optional App Walkthrough (device-local; tour dismissal syncs via RPC).
enum PostAuthOnboardingWelcomeStore {
    enum Choice: String, Sendable {
        case tour
        case later
    }

    private static func respondedKey(_ profileID: ProfileID) -> String {
        "tt.postAuthOnboarding.welcome.responded.\(profileID.rawValue)"
    }

    static func hasResponded(profileID: ProfileID) -> Bool {
        UserDefaults.standard.string(forKey: respondedKey(profileID)) != nil
    }

    static func choice(for profileID: ProfileID) -> Choice? {
        guard let raw = UserDefaults.standard.string(forKey: respondedKey(profileID)) else { return nil }
        return Choice(rawValue: raw)
    }

    static func record(profileID: ProfileID, choice: Choice) {
        UserDefaults.standard.set(choice.rawValue, forKey: respondedKey(profileID))
    }

    static func clear(for profileID: ProfileID) {
        UserDefaults.standard.removeObject(forKey: respondedKey(profileID))
    }
}

/// Native post-auth funnel vs returning web accounts.
enum PostAuthOnboardingPolicy {
    private static let planProgress = PostOnboardingPlanSelectionProgressStore()
    private static let tourProgress = ContextualTourProgressStore()

    static func effectiveTourDismissedVersion(userID: String) -> Int {
        let local = tourProgress.dismissedVersion(for: .dashboard, userID: userID)
        return max(local, NativeIosOnboardingSessionStore.tourDismissedVersion)
    }

    static func hasSatisfiedNativePlanStep(userID: String) -> Bool {
        planProgress.hasCompleted(userID: userID)
            || NativeIosOnboardingSessionStore.planAcknowledged
    }

    /// New native funnel only. Web-complete accounts never see plan again.
    static func shouldPresentPlanSelection(profileID: ProfileID, accountCreatedAt: Date?) -> Bool {
        guard isInPostAuthFunnel(profileID: profileID) else { return false }
        guard !NativeIosOnboardingSessionStore.onboardingCompleted else { return false }
        guard !hasSatisfiedNativePlanStep(userID: profileID.rawValue) else { return false }
        return true
    }

    /// Main-shell plan sheet for reinstall edge cases — never for web-complete profiles.
    static func shouldPresentPlanOnMainShell(userID: String) -> Bool {
        guard !NativeIosOnboardingSessionStore.onboardingCompleted else { return false }
        let profileID = ProfileID(userID)
        guard isInPostAuthFunnel(profileID: profileID) else { return false }
        return !hasSatisfiedNativePlanStep(userID: userID)
    }

    static func isInPostAuthFunnel(profileID: ProfileID) -> Bool {
        switch BrokerOnboardingPersistence.status(for: profileID) {
        case .pending:
            return true
        case .finished:
            if let step = PostAuthOnboardingProgress.currentStep(for: profileID) {
                return step != .finished
            }
            return false
        case .unknown:
            return false
        }
    }

    /// After native plan step (funnel users).
    static func shouldArmWalkthroughAfterPlan(profileID: ProfileID) -> Bool {
        guard hasSatisfiedNativePlanStep(userID: profileID.rawValue) else { return false }
        return shouldPresentAutomaticWalkthrough(profileID: profileID)
    }

    /// Welcome modal before the first automatic walkthrough offer.
    static func shouldPresentWelcomeModal(profileID: ProfileID) -> Bool {
        guard shouldPresentAutomaticWalkthrough(profileID: profileID) else { return false }
        guard !PostAuthOnboardingWelcomeStore.hasResponded(profileID: profileID) else { return false }
        return true
    }

    /// Automatic presentation — no account creation date cutoff.
    static func shouldPresentAutomaticWalkthrough(profileID: ProfileID) -> Bool {
        let tourVersion = ContextualTourCatalog.dashboard.version
        guard effectiveTourDismissedVersion(userID: profileID.rawValue) < tourVersion else { return false }

        if isInPostAuthFunnel(profileID: profileID) {
            return hasSatisfiedNativePlanStep(userID: profileID.rawValue)
        }
        if NativeIosOnboardingSessionStore.onboardingCompleted {
            return true
        }
        return false
    }
}