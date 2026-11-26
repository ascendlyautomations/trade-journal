import CoreGraphics
import Foundation
import Observation

enum ContextualTourPhase: Equatable {
    case idle
    case measuring
    case presenting
}

/// Decides when the app walkthrough may appear. Screens only mark targets.
@MainActor
@Observable
final class ContextualTourCoordinator {
    static let shared = ContextualTourCoordinator()

    private let progress: ContextualTourProgressStore
    private let cutoff: Date
    private let definition: ContextualTourDefinition
    private let schedulesAsyncResolution: Bool

    private(set) var phase: ContextualTourPhase = .idle
    private(set) var stepIndex: Int = 0
    private(set) var spotlightFrame: CGRect = .zero
    private(set) var scrollTarget: ContextualTourTargetID?
    /// Bumps on every autoscroll request so list screens re-run `scrollTo` even for the same target.
    private(set) var scrollGeneration: UInt64 = 0
    /// Set when the next spotlight lives on another screen. The shell performs the navigation.
    private(set) var navigationRequest: ContextualTourSurface?
    /// Shown after Exit. Nil while the walkthrough is running.
    private(set) var exitNotice: String?
    private(set) var shouldOpenTradingRulesAfterCompletion = false

    private var userID: String?
    private var createdAt: Date?
    private var gates = ContextualTourGates()
    private var analyticsReady = false
    private var feedChromeReady = false
    private var replayArmed = false
    /// Stops an exhausted pass from immediately re-arming until the user leaves Dashboard.
    private var suppressedUntilGatesDrop = false
    /// Arms the one-time post-plan walkthrough without requiring dashboard analytics.
    private var postPlanWalkthroughArmed = false
    private var resolveStartedAt: Date?
    private var previousFrame: CGRect?
    private var scrollIssuedForStep: Int?
    private var scrollRetryCountForStep: Int = 0
    private var lastViewport: CGRect?
    private var lastTopInset: CGFloat = 0
    private var lastBottomInset: CGFloat = 0
    private var measurementToken: UInt64 = 0
    private var timeoutTask: Task<Void, Never>?
    private var confirmationTask: Task<Void, Never>?
    private var hasPresentedStep = false
    private var displayedStepIndex = 0

    init(
        progress: ContextualTourProgressStore? = nil,
        cutoff: Date? = nil,
        definition: ContextualTourDefinition? = nil,
        schedulesAsyncResolution: Bool = true
    ) {
        self.progress = progress ?? ContextualTourProgressStore()
        self.cutoff = cutoff ?? ContextualTourLaunch.accountCreatedAtCutoff
        self.definition = definition ?? ContextualTourCatalog.dashboard
        self.schedulesAsyncResolution = schedulesAsyncResolution
    }

    var isPresenting: Bool { phase == .presenting }

    /// True from the first resolved step until Skip or Got It. Stays true while the next target is measured.
    var showsOverlay: Bool {
        phase == .presenting || (phase == .measuring && hasPresentedStep)
    }

    var currentStep: ContextualTourStep? {
        guard definition.steps.indices.contains(stepIndex) else { return nil }
        return definition.steps[stepIndex]
    }

    var progressLabel: String {
        guard let position = progressPosition(for: visibleStepIndex) else { return "" }
        return "\(position.index + 1) of \(position.total)"
    }

    var isFinalStep: Bool {
        switch currentStep?.role {
        case .finish, .tradingRulesPrompt:
            return true
        default:
            return false
        }
    }

    /// Full explanation card during presenting; spotlight steps also explain while measuring once a hole exists.
    var showsExplanationCard: Bool {
        guard currentStep?.role.countsTowardProgress ?? false else { return false }
        switch phase {
        case .presenting:
            return true
        case .measuring:
            return currentStep?.role == .spotlight
        case .idle:
            return false
        }
    }

    /// Step the card should explain. The next step's copy waits until its anchor is ready.
    var visibleStep: ContextualTourStep? {
        guard definition.steps.indices.contains(visibleStepIndex) else { return nil }
        return definition.steps[visibleStepIndex]
    }

    /// Anchor the overlay should measure. Prompts have no hole.
    var spotlightTarget: ContextualTourTargetID? {
        guard let step = currentStep else { return nil }
        switch step.role {
        case .spotlight, .narration:
            return step.target
        case .sectionContinue, .finish, .tradingRulesPrompt:
            return nil
        }
    }

    var visibleStepIndex: Int {
        switch phase {
        case .presenting, .measuring:
            return stepIndex
        case .idle:
            return displayedStepIndex
        }
    }

    /// Feed filters step, keep the horizontal filter strip visible and sized intrinsically for measurement.
    var pinsFeedFilterBar: Bool {
        guard phase == .measuring || phase == .presenting else { return false }
        return currentStep?.target == .feedContentFilters
    }

    /// Geometry stays dormant unless this target is the step being measured or shown.
    func measures(_ target: ContextualTourTargetID) -> Bool {
        guard phase == .measuring || phase == .presenting else { return false }
        return spotlightTarget == target
    }

    func setDashboardAnalyticsReady(_ ready: Bool) {
        guard analyticsReady != ready else { return }
        analyticsReady = ready
        reevaluate()
    }

    func setFeedChromeReady(_ ready: Bool) {
        guard feedChromeReady != ready else { return }
        feedChromeReady = ready
        reevaluate()
    }

    func syncShell(userID: String?, createdAt: Date?, gates: ContextualTourGates) {
        if userID != self.userID {
            clearMemory()
            postPlanWalkthroughArmed = false
        }
        self.userID = userID
        if let createdAt, ContextualTourEligibility.isAuthoritativeCreatedAt(createdAt) {
            self.createdAt = createdAt
        } else if createdAt == nil {
            self.createdAt = nil
        }
        self.gates = gates
        reevaluate()
    }

    func refreshAccountCreatedAt(_ createdAt: Date?) {
        guard let createdAt, ContextualTourEligibility.isAuthoritativeCreatedAt(createdAt) else { return }
        guard self.createdAt != createdAt else { return }
        self.createdAt = createdAt
        reevaluate()
    }

    func notePostOnboardingWalkthroughShouldPresent(userID: String?) {
        guard let userID, !userID.isEmpty else { return }
        let profileID = ProfileID(userID)
        guard PostAuthOnboardingPolicy.shouldPresentAutomaticWalkthrough(profileID: profileID) else {
            return
        }
        postPlanWalkthroughArmed = true
        suppressedUntilGatesDrop = false
        reevaluate()
    }

    /// Walkthrough state for the analytics-preferences invitation.
    func analyticsPreferenceTourGate() -> (eligible: Bool, settled: Bool, blocking: Bool) {
        let eligible = ContextualTourEligibility.isAccountEligible(createdAt: createdAt, cutoff: cutoff)
        let settled: Bool
        if let userID {
            settled = progress.dismissedVersion(for: definition.id, userID: userID) >= definition.version
        } else {
            settled = false
        }
        return (eligible, settled, phase != .idle)
    }

    /// In-memory replay. Does not lower or rewrite a stored dismissed version.
    func beginReplay() {
        exitNotice = nil
        replayArmed = true
        suppressedUntilGatesDrop = false
        stepIndex = 0
        hideWithoutDismiss(resetStep: true)
        reevaluate()
    }

    func skip() {
        acknowledge()
    }

    /// Leaves the walkthrough from any step and tells the user how to start it again.
    func exitTour() {
        exitNotice = "You can restart the App Walkthrough anytime from Settings."
        acknowledge()
    }

    func clearExitNotice() {
        exitNotice = nil
    }

    func advance() {
        guard phase == .presenting else { return }
        if stepIndex >= definition.steps.count - 1 {
            acknowledge()
        } else {
            stepIndex += 1
            beginMeasuring()
        }
    }

    /// Ends the tour and optionally opens Trading Rules after the overlay dismisses.
    func completeTour(configureTradingRules: Bool) {
        shouldOpenTradingRulesAfterCompletion = configureTradingRules
        acknowledge()
    }

    func consumeOpenTradingRulesAfterCompletion() -> Bool {
        let open = shouldOpenTradingRulesAfterCompletion
        shouldOpenTradingRulesAfterCompletion = false
        return open
    }

    #if DEBUG
    /// Clears this user's stored dismissal and arms the tour again on the next eligible Dashboard.
    func resetStoredTourForDebug() {
        if let userID, !userID.isEmpty {
            progress.clearDismissals(userID: userID)
        }
        replayArmed = false
        suppressedUntilGatesDrop = false
        hideWithoutDismiss(resetStep: true)
        reevaluate()
    }
    #endif

    /// Logout and account switches drop in-memory tour state only.
    func resetForSessionBoundary() {
        clearMemory()
        userID = nil
        createdAt = nil
        gates = ContextualTourGates()
        analyticsReady = false
        feedChromeReady = false
        exitNotice = nil
        shouldOpenTradingRulesAfterCompletion = false
        postPlanWalkthroughArmed = false
    }

    func noteMeasuredFrame(
        _ frame: CGRect?,
        viewport: CGRect,
        topInset: CGFloat,
        bottomInset: CGFloat,
        now: Date = Date()
    ) {
        guard phase == .measuring || phase == .presenting, currentStep != nil else { return }

        if phase == .presenting {
            return
        }

        lastViewport = viewport
        lastTopInset = topInset
        lastBottomInset = bottomInset

        if let frame,
           ContextualTourGeometry.isUsable(frame),
           let target = spotlightTarget,
           !ContextualTourGeometry.skipsTourAutoscroll(for: target),
           ContextualTourGeometry.needsScroll(
            frame: frame,
            viewport: viewport,
            topInset: topInset,
            bottomInset: bottomInset
           ) {
            if scrollIssuedForStep != stepIndex {
                issueScroll(now: now)
            } else if scrollRetryCountForStep < settingsListScrollRetries(for: target) {
                scrollRetryCountForStep += 1
                issueScroll(now: now)
            }
            return
        }

        guard let frame, ContextualTourGeometry.isUsable(frame) else {
            return
        }

        if spotlightTarget == .feedContentFilters,
           ContextualTourGeometry.isMeasurableTarget(frame, in: viewport),
           FeedFilterBarTourLayoutGate.mayMeasure
        {
#if DEBUG
            ContextualTourDebug.log(
                "feedFilters measure viewport=\(viewport) frame=\(frame) retained=\(spotlightFrame)"
            )
#endif
            presentResolvedStep(frame: frame)
            return
        }

        let elapsed = now.timeIntervalSince(resolveStartedAt ?? now)
        switch ContextualTourGeometry.resolve(frame: frame, previous: previousFrame, elapsed: elapsed) {
        case .ready(let stable):
            let visible = ContextualTourGeometry.measurementVisibleRect(
                viewport: viewport,
                topInset: topInset,
                bottomInset: bottomInset
            )
            if ContextualTourGeometry.isRenderableSpotlight(stable, in: visible) {
                presentResolvedStep(frame: stable)
            } else {
                previousFrame = stable
            }
        case .waiting:
            let needsConfirmation = previousFrame == nil
            previousFrame = frame
            if needsConfirmation {
                scheduleConfirmation(of: frame, viewport: viewport, topInset: topInset, bottomInset: bottomInset)
            }
        case .skip:
            previousFrame = frame
        }
    }

    /// Scrolls once when the anchor is missing, then skips only that step if it never appears.
    /// Cross-screen steps wait until the destination surface exists instead of skipping on a timer.
    func forceTimeout(now: Date = Date()) {
        guard phase == .measuring else { return }
        if let step = currentStep, !isSurfaceReady(step) {
            navigationRequest = step.surface
            if schedulesAsyncResolution {
                scheduleTimeout()
                return
            }
        }
        if scrollIssuedForStep != stepIndex {
            issueScroll(now: now)
            return
        }
        let elapsed = now.timeIntervalSince(resolveStartedAt ?? now)
        guard elapsed >= ContextualTourGeometry.resolveTimeout(for: spotlightTarget) else { return }
        let maxScrollRetries = settingsListScrollRetries(for: spotlightTarget)
        if scrollIssuedForStep == stepIndex,
           scrollRetryCountForStep < maxScrollRetries
        {
            scrollRetryCountForStep += 1
            issueScroll(now: now)
            return
        }
        skipUnresolvedStep()
    }

    /// Dashboard sections (e.g. Getting Started) resized during measurement — re-scroll and re-stabilize.
    func noteScrollTargetLayoutChanged() {
        guard phase == .measuring else { return }
        guard let target = spotlightTarget else { return }
        guard !ContextualTourGeometry.skipsTourAutoscroll(for: target) else { return }
        previousFrame = nil
        resolveStartedAt = Date()
        if scrollIssuedForStep == stepIndex {
            let maxRetries = settingsListScrollRetries(for: target)
            guard scrollRetryCountForStep < maxRetries else { return }
            scrollRetryCountForStep += 1
            issueScroll(now: Date())
        }
    }

    private func presentResolvedStep(frame: CGRect) {
        guard let step = currentStep else { return }
        switch step.role {
        case .spotlight:
            guard let viewport = lastViewport,
                  ContextualTourGeometry.isRenderableSpotlight(
                    frame,
                    in: ContextualTourGeometry.measurementVisibleRect(
                        viewport: viewport,
                        topInset: lastTopInset,
                        bottomInset: lastBottomInset
                    )
                  )
            else {
                return
            }
        case .narration:
            guard ContextualTourGeometry.isUsable(frame),
                  let viewport = lastViewport,
                  ContextualTourGeometry.isRenderableSpotlight(frame, in: viewport)
            else {
                return
            }
        case .sectionContinue, .finish, .tradingRulesPrompt:
            break
        }

        confirmationTask?.cancel()
        timeoutTask?.cancel()
        spotlightFrame = frame
        scrollTarget = nil
        displayedStepIndex = stepIndex
        hasPresentedStep = true
        phase = .presenting
        ContextualTourDebug.logAppTour("presenting")
    }

    private func reevaluate() {
        guard let userID, !userID.isEmpty else {
            logDecision("blocked.no-user")
            ContextualTourDebug.logAppTour("suppressed reason=no-user")
            hideWithoutDismiss(resetStep: true)
            return
        }

        let shellReady = shellReadyForCurrentStep()
        if !shellReady {
            if isWaitingForRequestedSurface() {
                logDecision("waiting.surface")
                ContextualTourDebug.logAppTour("waiting surface=\(currentStep?.surface.rawValue ?? "none")")
                return
            }
            if hasPresentedStep,
               phase == .measuring || phase == .presenting,
               currentStep?.surface == .profile {
                logDecision("waiting.profile-shell")
                ContextualTourDebug.logAppTour("waiting profile-shell")
                return
            }
            if gates.sceneActive && gates.unobstructed,
               let step = currentStep,
               navigationRequest == step.surface,
               phase == .idle {
                logDecision("waiting.navigation")
                return
            }
            suppressedUntilGatesDrop = false
            let reason = gates.sceneActive && gates.unobstructed ? "surface-not-ready" : "shell"
            logDecision("blocked.\(reason)")
            ContextualTourDebug.logAppTour("suppressed reason=\(reason)")
            hideWithoutDismiss(resetStep: false)
            return
        }
        if navigationRequest != nil {
            navigationRequest = nil
        }
        if suppressedUntilGatesDrop {
            logDecision("blocked.suppressed-until-dashboard-left")
            ContextualTourDebug.logAppTour("suppressed reason=left-dashboard")
            return
        }

        let dismissed = PostAuthOnboardingPolicy.effectiveTourDismissedVersion(userID: userID)
        let policyAutomatic = PostAuthOnboardingPolicy.shouldPresentAutomaticWalkthrough(
            profileID: ProfileID(userID)
        )
        guard replayArmed || postPlanWalkthroughArmed || policyAutomatic else {
            let epoch = createdAt == Date(timeIntervalSince1970: 0)
            let reason: String
            if epoch {
                reason = "created-at-missing"
                logDecision("blocked.created-at-epoch-fallback")
            } else if dismissed >= definition.version {
                reason = "completed"
                logDecision("blocked.dismissed")
            } else {
                reason = "before-cutoff"
                logDecision("blocked.before-cutoff")
            }
            ContextualTourDebug.logAppTour("suppressed reason=\(reason)")
            hideWithoutDismiss(resetStep: true)
            return
        }

        switch phase {
        case .measuring, .presenting:
            logDecision("armed.\(phase)")
            return
        case .idle:
            logDecision(replayArmed ? "arm.replay" : "arm.automatic")
            if !replayArmed {
                ContextualTourDebug.logAppTour("eligible")
            }
            beginMeasuring()
        }
    }

    private func logDecision(_ reason: String) {
        let created = createdAt.map { ISO8601.string(from: $0) } ?? "nil"
        let dismissed = userID.map { progress.dismissedVersion(for: definition.id, userID: $0) } ?? -1
        ContextualTourDebug.log(
            "\(reason) createdAt=\(created) cutoff=\(ISO8601.string(from: cutoff)) dismissed=\(dismissed) tour=\(definition.version) homeRoot=\(gates.homeRootActive) scene=\(gates.sceneActive) unobstructed=\(gates.unobstructed) analytics=\(analyticsReady) phase=\(phase)"
        )
    }

    private func isSurfaceReady(_ step: ContextualTourStep) -> Bool {
        guard gates.sceneActive, gates.unobstructed else { return false }
        switch step.surface {
        case .dashboard:
            if postPlanWalkthroughArmed || replayArmed {
                return gates.homeRootActive
            }
            return gates.homeRootActive && analyticsReady
        case .feed:
            return gates.feedRootActive && feedChromeReady
        case .messages:
            return gates.messagesRootActive
        case .profile:
            return gates.profileRootActive
        case .settings:
            return gates.settingsHomeActive
        case .payouts:
            return gates.payoutsActive
        case .expenseTracker:
            return gates.expenseTrackerActive
        case .trades:
            return gates.tradesActive
        }
    }

    /// Idle step 0 is the Dashboard auto-start. A paused later step resumes on its own surface.
    private func shellReadyForCurrentStep() -> Bool {
        if phase == .idle && stepIndex == 0 {
            return isSurfaceReady(
                ContextualTourStep(
                    title: "",
                    message: "",
                    surface: .dashboard
                )
            )
        }
        guard let step = currentStep else { return false }
        return isSurfaceReady(step)
    }

    private func isWaitingForRequestedSurface() -> Bool {
        guard let step = currentStep, navigationRequest == step.surface else { return false }
        guard gates.sceneActive, gates.unobstructed else { return false }
        return phase == .measuring || phase == .presenting
    }

    private func beginMeasuring() {
        skipSectionContinueSteps()
        guard let step = currentStep else {
            finishWithoutDismiss()
            return
        }
        measurementToken &+= 1
        timeoutTask?.cancel()
        confirmationTask?.cancel()
        previousFrame = nil
        scrollIssuedForStep = nil
        scrollRetryCountForStep = 0
        scrollTarget = nil
        spotlightFrame = .zero
        lastViewport = nil
        ContextualTourGlobalFrameStore.shared.reset()
        resolveStartedAt = Date()
        if step.target == .feedContentFilters {
            FeedFilterBarTourLayoutGate.resetForTourStep()
        } else {
            FeedFilterBarTourLayoutGate.clear()
        }
        navigationRequest = isSurfaceReady(step) ? nil : step.surface
        if step.role != .spotlight {
            presentResolvedStep(frame: .zero)
            return
        }
        phase = .measuring
        if let target = step.target,
           step.role == .spotlight,
           !ContextualTourGeometry.skipsTourAutoscroll(for: target)
        {
            issueScroll(now: Date())
        }
        scheduleTimeout()
    }

    private func issueScroll(now: Date) {
        scrollIssuedForStep = stepIndex
        if let target = spotlightTarget, ContextualTourGeometry.skipsTourAutoscroll(for: target) {
            previousFrame = nil
            resolveStartedAt = now
            scheduleTimeout()
            return
        }
        scrollGeneration &+= 1
        scrollTarget = spotlightTarget
        previousFrame = nil
        resolveStartedAt = now
        scheduleTimeout()
    }

    private func scheduleTimeout() {
        guard schedulesAsyncResolution else { return }
        timeoutTask?.cancel()
        let token = measurementToken
        timeoutTask = Task { @MainActor in
            let timeout = ContextualTourGeometry.resolveTimeout(for: spotlightTarget)
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled, token == measurementToken, phase == .measuring else { return }
            forceTimeout()
        }
    }

    private func scheduleConfirmation(
        of frame: CGRect,
        viewport: CGRect,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) {
        guard schedulesAsyncResolution else { return }
        confirmationTask?.cancel()
        let token = measurementToken
        confirmationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled, token == measurementToken, phase == .measuring else { return }
            noteMeasuredFrame(
                frame,
                viewport: viewport,
                topInset: topInset,
                bottomInset: bottomInset
            )
        }
    }

    private func skipUnresolvedStep() {
        timeoutTask?.cancel()
        confirmationTask?.cancel()
        let next = stepIndex + 1
        if next >= definition.steps.count {
            finishWithoutDismiss()
            return
        }
        if definition.steps[next].role == .tradingRulesPrompt {
            finishWithoutDismiss()
            return
        }
        stepIndex = next
        beginMeasuring()
    }

    private func acknowledge() {
        let persistDismissal = !replayArmed
        let completedUserID = persistDismissal ? userID : nil
        if let userID, persistDismissal {
            progress.dismiss(definition.id, version: definition.version, userID: userID)
            ContextualTourDebug.logAppTour("completed")
            PostAuthOnboardingProgress.markWalkthroughFinished(for: ProfileID(userID))
            NativeIosOnboardingSync.recordTourDismissed(
                userID: userID,
                version: definition.version,
                rpc: NativeIosOnboardingServices.rpc
            )
        }
        replayArmed = false
        postPlanWalkthroughArmed = false
        suppressedUntilGatesDrop = true
        hideWithoutDismiss(resetStep: true)
        if let completedUserID {
            NotificationCenter.default.post(
                name: .contextualTourDidComplete,
                object: completedUserID
            )
        }
    }

    private func finishWithoutDismiss() {
        if hasPresentedStep {
            suppressedUntilGatesDrop = true
        } else {
            suppressedUntilGatesDrop = false
        }
        replayArmed = false
        hideWithoutDismiss(resetStep: true)
        if postPlanWalkthroughArmed {
            reevaluate()
        }
    }

    private func hideWithoutDismiss(resetStep: Bool) {
        timeoutTask?.cancel()
        confirmationTask?.cancel()
        measurementToken &+= 1
        phase = .idle
        scrollTarget = nil
        spotlightFrame = .zero
        previousFrame = nil
        ContextualTourGlobalFrameStore.shared.reset()
        hasPresentedStep = false
        displayedStepIndex = 0
        if resetStep {
            stepIndex = 0
            navigationRequest = nil
        }
    }

    private func clearMemory() {
        hideWithoutDismiss(resetStep: true)
        replayArmed = false
        suppressedUntilGatesDrop = false
    }

    private func skipSectionContinueSteps() {
        while let step = currentStep, step.role == .sectionContinue {
            let nextIndex = stepIndex + 1
            guard nextIndex < definition.steps.count else {
                stepIndex = nextIndex
                return
            }
            navigationRequest = definition.steps[nextIndex].surface
            stepIndex = nextIndex
        }
    }

    private func settingsListScrollRetries(for target: ContextualTourTargetID?) -> Int {
        switch target {
        case .settingsAppearance, .settingsTradingRules:
            return 3
        case .dashboardPerformance:
            return 3
        case .dashboardAccountAndDates:
            return 4
        default:
            return 2
        }
    }

    private func progressPosition(for stepIndex: Int) -> (index: Int, total: Int)? {
        let indexed = definition.steps.enumerated().filter { $0.element.role.countsTowardProgress }
        let total = indexed.count
        guard total > 0 else { return nil }
        guard let match = indexed.firstIndex(where: { $0.offset == stepIndex }) else { return nil }
        return (match, total)
    }
}
