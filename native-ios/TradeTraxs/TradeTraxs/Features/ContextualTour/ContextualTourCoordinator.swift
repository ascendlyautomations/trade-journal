import CoreGraphics
import Foundation
import Observation

enum ContextualTourPhase: Equatable {
    case idle
    case preparing
    case presenting
}

private enum WalkthroughActivation: Equatable {
    case automatic
    case welcomeTakeTour
    case settingsReplay
}

/// Orchestrates the app walkthrough: idle → preparing (non-blocking) → presenting (blocking overlay).
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
    private(set) var stepRevision: UInt64 = 0
    private(set) var spotlightFrame: CGRect = .zero
    private(set) var scrollTarget: ContextualTourTargetID?
    private(set) var scrollGeneration: UInt64 = 0
  private(set) var navigationRequest: ContextualTourSurface?
    private(set) var exitNotice: String?
    private(set) var shouldOpenTradingRulesAfterCompletion = false
    private(set) var presentedStepRevision: UInt64 = 0

    private var sessionID: UInt64 = 0
    private var activation: WalkthroughActivation?
    private var pendingAutomaticArm = false
    private var persistDismissalOnAcknowledge = true
    private var navigationSatisfiedForStepIndex: Int?
    private var scrollIssuedForStepIndex: Int?
    private var profileIdentityHeaderHydrated = false
    private var stabilityCandidateFrame: CGRect?
    private var presentingStabilityFrame: CGRect?
    private var lastViewport: CGRect?
    private var lastTopInset: CGFloat = 0
    private var lastBottomInset: CGFloat = 0

    private var userID: String?
    private var createdAt: Date?
    private var gates = ContextualTourGates()
    private var preparationTimeoutGeneration: UInt64 = 0
    /// Prevents automatic re-arm after a cancelled or timed-out session until explicit user activation.
    private var blocksAutomaticRestart = false

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

    var showsOverlay: Bool {
        phase == .presenting && canShowBlockingChrome
    }

    var showsExplanationCard: Bool {
        guard phase == .presenting, let step = visibleStep else { return false }
        switch step.role {
        case .spotlight, .narration, .finish, .tradingRulesPrompt:
            return true
        case .sectionContinue:
            return false
        }
    }

    var currentStep: ContextualTourStep? {
        guard definition.steps.indices.contains(stepIndex) else { return nil }
        return definition.steps[stepIndex]
    }

    var visibleStep: ContextualTourStep? { currentStep }

    var visibleStepIndex: Int { stepIndex }

    var progressLabel: String {
        guard let position = progressPosition(for: stepIndex) else { return "" }
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

    var spotlightTarget: ContextualTourTargetID? {
        guard let step = currentStep else { return nil }
        switch step.role {
        case .spotlight, .narration:
            return step.target
        case .sectionContinue, .finish, .tradingRulesPrompt:
            return nil
        }
    }

    var pinsFeedFilterBar: Bool {
        guard phase == .preparing || phase == .presenting else { return false }
        return currentStep?.target == .feedContentFilters
    }

    var walkthroughSessionID: UInt64 { sessionID }

    func measures(_ target: ContextualTourTargetID) -> Bool {
        guard phase == .preparing || phase == .presenting else { return false }
        return spotlightTarget == target
    }

    func acceptsGlobalMeasurement(for target: ContextualTourTargetID) -> Bool {
        guard measures(target), let step = currentStep else {
            if target == .mainTabHome {
                ContextualTourDebug.logTourTrace("acceptsGlobalMeasurement(mainTabHome)=false measures/step failed")
            }
            return false
        }
        let ready = isSurfaceReady(step)
        if target == .mainTabHome {
            ContextualTourDebug.logTourTrace(
                "acceptsGlobalMeasurement(mainTabHome)=\(ready) surface=\(step.surface) homeRoot=\(gates.homeRootActive)"
            )
        }
        return ready
    }

    // MARK: - Shell sync

    func syncShell(userID: String?, createdAt: Date?, gates: ContextualTourGates) {
        ContextualTourDebug.logTourTrace(
            "syncShell phase=\(phase) session=\(sessionID) homeRoot=\(gates.homeRootActive) scene=\(gates.sceneActive) unobstructed=\(gates.unobstructed)"
        )
        if userID != self.userID {
            terminateSession(reason: "user-changed")
            self.userID = userID
            activation = nil
            pendingAutomaticArm = false
        } else {
            self.userID = userID
        }
        if let createdAt, ContextualTourEligibility.isAuthoritativeCreatedAt(createdAt) {
            self.createdAt = createdAt
        } else if createdAt == nil {
            self.createdAt = nil
        }
        self.gates = gates

        switch phase {
        case .idle:
            tryStartAutomaticSessionIfEligible()
        case .preparing:
            handlePreparingShellUpdate()
        case .presenting:
            handlePresentingShellUpdate()
        }
    }

    func refreshAccountCreatedAt(_ createdAt: Date?) {
        guard let createdAt, ContextualTourEligibility.isAuthoritativeCreatedAt(createdAt) else { return }
        guard self.createdAt != createdAt else { return }
        self.createdAt = createdAt
        if phase == .idle {
            tryStartAutomaticSessionIfEligible()
        }
    }

    // MARK: - Activation (single pipeline)

    func notePostOnboardingWalkthroughShouldPresent(userID: String?) {
        ContextualTourDebug.logTourTrace("notePostOnboardingWalkthroughShouldPresent userID=\(userID ?? "nil")")
        guard let userID, !userID.isEmpty else {
            ContextualTourDebug.logTourTrace("post-plan arm rejected missing-user")
            return
        }
        let profileID = ProfileID(userID)
        guard PostAuthOnboardingPolicy.shouldPresentAutomaticWalkthrough(profileID: profileID) else {
            ContextualTourDebug.logTourTrace("post-plan arm rejected policy")
            return
        }
        pendingAutomaticArm = true
        blocksAutomaticRestart = false
        tryStartAutomaticSessionIfEligible()
    }

    func beginWelcomeTakeTour() {
        ContextualTourDebug.logTourTrace("coordinator beginWelcomeTakeTour invoked")
        startSession(activation: .welcomeTakeTour)
    }

    func beginReplay() {
        ContextualTourDebug.logTourTrace("coordinator beginReplay invoked", force: true)
        startSession(activation: .settingsReplay, persistDismissal: false)
    }

    private func startSession(activation: WalkthroughActivation, persistDismissal: Bool = true) {
        ContextualTourDebug.logTourTrace(
            "startSession activation=\(activation) persistDismissal=\(persistDismissal) priorPhase=\(phase)",
            force: true
        )
        exitNotice = nil
        pendingAutomaticArm = false
        blocksAutomaticRestart = false
        cancelPreparationTimeout()
        ContextualTourGlobalFrameStore.shared.reset()
        phase = .idle
        spotlightFrame = .zero
        scrollTarget = nil
        stabilityCandidateFrame = nil
        presentingStabilityFrame = nil
        navigationSatisfiedForStepIndex = nil
        scrollIssuedForStepIndex = nil
        profileIdentityHeaderHydrated = false
        navigationRequest = nil
        presentedStepRevision = 0
        stepRevision = 0
        self.activation = activation
        persistDismissalOnAcknowledge = persistDismissal
        sessionID &+= 1
        stepIndex = 0
        beginPreparing()
        if activation == .settingsReplay || activation == .welcomeTakeTour {
            navigationSatisfiedForStepIndex = nil
            navigationRequest = .dashboard
            ContextualTourDebug.logTourTrace(
                "explicit walkthrough start navigation-request=dashboard session=\(sessionID)",
                force: true
            )
        }
        ContextualTourDebug.logTourTrace(
            "session activated id=\(sessionID) activation=\(activation) phase=\(phase) stepRevision=\(stepRevision)",
            force: true
        )
    }

    private func tryStartAutomaticSessionIfEligible() {
        guard phase == .idle, activation == nil else {
            ContextualTourDebug.logTourTrace(
                "automatic start rejected phase=\(phase) activation=\(String(describing: activation))"
            )
            return
        }
        guard !blocksAutomaticRestart else {
            ContextualTourDebug.logTourTrace("automatic start rejected blocksAutomaticRestart=true")
            return
        }
        guard let userID, !userID.isEmpty else {
            ContextualTourDebug.logTourTrace("automatic start rejected missing-user")
            return
        }
        guard gates.sceneActive, gates.unobstructed else {
            ContextualTourDebug.logTourTrace(
                "automatic start rejected shell gates scene=\(gates.sceneActive) unobstructed=\(gates.unobstructed)"
            )
            return
        }

        let policyAutomatic = PostAuthOnboardingPolicy.shouldPresentAutomaticWalkthrough(
            profileID: ProfileID(userID)
        )
        guard pendingAutomaticArm || policyAutomatic else {
            ContextualTourDebug.logTourTrace(
                "automatic start rejected policy pending=\(pendingAutomaticArm) policyAutomatic=\(policyAutomatic)"
            )
            return
        }

        let dismissed = PostAuthOnboardingPolicy.effectiveTourDismissedVersion(userID: userID)
        guard dismissed < definition.version else {
            pendingAutomaticArm = false
            ContextualTourDebug.logTourTrace("automatic start rejected dismissed=\(dismissed) tour=\(definition.version)")
            return
        }

        if !ContextualTourEligibility.isAccountEligible(createdAt: createdAt, cutoff: cutoff) {
            ContextualTourDebug.logTourTrace(
                "automatic start rejected ineligible-created-at=\(String(describing: createdAt))"
            )
            return
        }

        activation = .automatic
        persistDismissalOnAcknowledge = true
        pendingAutomaticArm = false
        stepIndex = 0
        sessionID &+= 1
        ContextualTourDebug.logTourTrace("automatic session eligible sessionID=\(sessionID)")
        ContextualTourDebug.logAppTour("eligible")
        beginPreparing()
    }

    // MARK: - User actions

    func skip() { acknowledge() }

    func exitTour() {
        exitNotice = "You can restart the App Walkthrough anytime from Settings."
        acknowledge()
    }

    func clearExitNotice() {
        exitNotice = nil
    }

    func advance() {
        guard phase == .presenting else {
            ContextualTourDebug.logTourTrace("advance rejected phase=\(phase)")
            return
        }
        if stepIndex >= definition.steps.count - 1 {
            acknowledge()
        } else {
            stepIndex += 1
            beginPreparing()
        }
    }

    /// Presents the Getting Started explanation without a spotlight when the checklist is not on the Dashboard.
    func commitGettingStartedExplanationOnlyIfNeeded() {
        guard phase == .preparing, let step = currentStep else { return }
        guard step.target == .dashboardGettingStarted, step.presentsIfUnmeasured else { return }
        guard isSurfaceReady(step) else { return }
        ContextualTourDebug.logTourTrace("getting started explanation-only step=\(stepIndex)")
        tryCommitPresentation(frame: .zero, revision: stepRevision)
    }

    func completeTour(configureTradingRules: Bool) {
        shouldOpenTradingRulesAfterCompletion = configureTradingRules
        acknowledge()
    }

    func consumeOpenTradingRulesAfterCompletion() -> Bool {
        let open = shouldOpenTradingRulesAfterCompletion
        shouldOpenTradingRulesAfterCompletion = false
        return open
    }

    func analyticsPreferenceTourGate() -> (eligible: Bool, settled: Bool, blocking: Bool) {
        let eligible = ContextualTourEligibility.isAccountEligible(createdAt: createdAt, cutoff: cutoff)
        let settled: Bool
        if let userID {
            settled = progress.dismissedVersion(for: definition.id, userID: userID) >= definition.version
        } else {
            settled = false
        }
        return (eligible, settled, showsOverlay)
    }

    func resetForSessionBoundary() {
        terminateSession(reason: "session-boundary")
        userID = nil
        createdAt = nil
        gates = ContextualTourGates()
        exitNotice = nil
        shouldOpenTradingRulesAfterCompletion = false
        pendingAutomaticArm = false
        blocksAutomaticRestart = false
    }

    #if DEBUG
    func resetStoredTourForDebug() {
        if let userID, !userID.isEmpty {
            progress.clearDismissals(userID: userID)
        }
        terminateSession(reason: "debug-reset")
    }
    #endif

    // MARK: - Navigation & scroll (once per step)

    func noteWalkthroughNavigationApplied(to surface: ContextualTourSurface) {
        guard phase == .preparing, let step = currentStep, step.surface == surface else {
            ContextualTourDebug.logTourTrace(
                "destination arrival ignored phase=\(phase) surface=\(surface) stepSurface=\(currentStep?.surface.rawValue ?? "nil")"
            )
            return
        }
        ContextualTourDebug.logTourTrace(
            "destination arrived surface=\(surface) step=\(stepIndex) target=\(step.target?.debugLabel ?? "none")"
        )
        navigationRequest = nil
        issueScrollIfNeeded()
    }

    func noteFeedFilterBarLaidOut() {}

    func noteSettingsHomeLaidOut() {}

    /// Step 15: loaded profile header is in the tree (natural layout, optional bio).
    func noteProfileIdentityHeaderHydrated() {
        guard phase == .preparing, spotlightTarget == .profileIdentity else { return }
        profileIdentityHeaderHydrated = true
    }

    func noteScrollTargetLayoutChanged() {
        guard phase == .preparing else { return }
        stabilityCandidateFrame = nil
    }

    // MARK: - Geometry pipeline

    func noteMeasuredFrame(
        _ frame: CGRect?,
        viewport: CGRect,
        topInset: CGFloat,
        bottomInset: CGFloat,
        revision: UInt64
    ) {
        ContextualTourDebug.logTourTrace(
            "noteMeasuredFrame received revision=\(revision) phase=\(phase) frame=\(frame?.debugDescription ?? "nil")"
        )
        guard revision == stepRevision else {
            let reason = "revision-mismatch expected=\(stepRevision) got=\(revision)"
            ContextualTourDebug.logMeasureReject(reason)
            ContextualTourDebug.logTourTrace("measurement rejected \(reason)")
            return
        }
        guard phase == .preparing, let step = currentStep else {
            let reason = "phase-or-step phase=\(phase) step=\(stepIndex)"
            ContextualTourDebug.logMeasureReject(reason)
            ContextualTourDebug.logTourTrace("measurement rejected \(reason)")
            return
        }
        guard isSurfaceReady(step) else {
            let reason = "surface-not-ready step=\(stepIndex) target=\(step.target?.debugLabel ?? "none") homeRoot=\(gates.homeRootActive)"
            ContextualTourDebug.logMeasureReject(reason)
            ContextualTourDebug.logTourTrace("measurement rejected \(reason)")
            return
        }

        lastViewport = viewport
        lastTopInset = topInset
        lastBottomInset = bottomInset

        if step.role == .tradingRulesPrompt || step.role == .finish {
            tryCommitPresentation(frame: .zero, revision: revision)
            return
        }

        guard let frame, ContextualTourGeometry.isUsable(frame) else {
            let reason = "missing-or-unusable-frame target=\(spotlightTarget?.debugLabel ?? "none")"
            ContextualTourDebug.logMeasureReject(reason)
            ContextualTourDebug.logTourTrace("measurement rejected \(reason)")
            return
        }

        let visible = ContextualTourGeometry.spotlightMeasurementVisibleRect(
            viewport: viewport,
            topInset: topInset,
            bottomInset: bottomInset,
            target: spotlightTarget
        )

        if let target = spotlightTarget,
           !ContextualTourGeometry.skipsTourAutoscroll(for: target),
           ContextualTourGeometry.needsScroll(frame: frame, viewport: viewport, topInset: topInset, bottomInset: bottomInset)
        {
            if scrollIssuedForStepIndex != stepIndex {
                let reason = "needs-scroll target=\(target.debugLabel)"
                ContextualTourDebug.logMeasureReject(reason)
                ContextualTourDebug.logTourTrace("measurement rejected \(reason)")
                issueScroll()
            }
            return
        }

        guard ContextualTourGeometry.isRenderableSpotlight(frame, in: visible) else {
            let reason = "not-renderable target=\(spotlightTarget?.debugLabel ?? "none") visible=\(visible)"
            ContextualTourDebug.logMeasureReject(reason)
            ContextualTourDebug.logTourTrace("measurement rejected \(reason)")
            return
        }

        if spotlightTarget == .profileIdentity {
            guard profileIdentityHeaderHydrated else {
                let reason = "profile-identity-header-not-hydrated"
                ContextualTourDebug.logMeasureReject(reason)
                ContextualTourDebug.logTourTrace("measurement rejected \(reason)")
                return
            }
            if let previous = stabilityCandidateFrame,
               ContextualTourGeometry.isStable(previous, frame)
            {
                stabilityCandidateFrame = nil
            } else {
                stabilityCandidateFrame = frame
                let reason = "profile-identity-awaiting-stable-frame"
                ContextualTourDebug.logMeasureReject(reason)
                ContextualTourDebug.logTourTrace("measurement rejected \(reason)")
                return
            }
        }

        ContextualTourDebug.logTourTrace(
            "measurement commit target=\(spotlightTarget?.debugLabel ?? "none")",
            force: true
        )
        tryCommitPresentation(frame: frame, revision: revision)
    }

    func notePresentingLayoutFrame(
        _ frame: CGRect?,
        viewport: CGRect,
        topInset: CGFloat,
        bottomInset: CGFloat,
        revision: UInt64
    ) {
        guard revision == presentedStepRevision, revision == stepRevision else {
            ContextualTourDebug.logTourTrace("notePresentingLayoutFrame rejected revision mismatch")
            return
        }
        guard phase == .presenting, let step = currentStep, step.role == .spotlight else {
            ContextualTourDebug.logTourTrace("notePresentingLayoutFrame rejected phase/role")
            return
        }
        guard let frame, ContextualTourGeometry.isUsable(frame) else {
            ContextualTourDebug.logTourTrace("notePresentingLayoutFrame rejected unusable frame")
            return
        }

        let visible = ContextualTourGeometry.measurementVisibleRect(
            viewport: viewport,
            topInset: topInset,
            bottomInset: bottomInset
        )
        guard ContextualTourGeometry.isRenderableSpotlight(frame, in: visible) else { return }
        guard ContextualTourGeometry.isStable(spotlightFrame, frame) == false else { return }

        var candidate = presentingStabilityFrame
        if ContextualTourGeometry.recordStabilityCandidate(frame, previous: &candidate) {
            spotlightFrame = frame
            presentingStabilityFrame = nil
        } else {
            presentingStabilityFrame = candidate
        }
    }

    // MARK: - Private

    private var canShowBlockingChrome: Bool {
        guard phase == .presenting, let step = currentStep else { return false }
        switch step.role {
        case .spotlight, .narration:
            if step.presentsIfUnmeasured, !ContextualTourGeometry.isUsable(spotlightFrame) {
                return true
            }
            guard ContextualTourGeometry.isUsable(spotlightFrame), let viewport = lastViewport else { return false }
            let visible = ContextualTourGeometry.spotlightMeasurementVisibleRect(
                viewport: viewport,
                topInset: lastTopInset,
                bottomInset: lastBottomInset,
                target: step.target
            )
            return ContextualTourGeometry.isRenderableSpotlight(spotlightFrame, in: visible)
        case .finish, .tradingRulesPrompt:
            return true
        case .sectionContinue:
            return false
        }
    }

    private func beginPreparing() {
        guard let step = currentStep else {
            ContextualTourDebug.logTourTrace("beginPreparing rejected no-step")
            terminateSession(reason: "no-step")
            return
        }

        let previousPhase = phase
        stepRevision &+= 1
        presentedStepRevision = 0
        phase = .preparing
        spotlightFrame = .zero
        scrollTarget = nil
        stabilityCandidateFrame = nil
        presentingStabilityFrame = nil
        navigationSatisfiedForStepIndex = nil
        scrollIssuedForStepIndex = nil
        profileIdentityHeaderHydrated = false
        navigationRequest = nil

        if stepIndex == 0 {
            ContextualTourCardPlacement.mainTabHomeRenderedCardBottom = nil
        }
        ContextualTourGlobalFrameStore.shared.reset()
        ContextualTourDebug.logPhaseTransition("\(previousPhase)", "preparing", "step=\(stepIndex) target=\(step.target?.debugLabel ?? "none")")
        ContextualTourDebug.logTourTrace(
            "phase transition \(previousPhase) -> preparing session=\(sessionID) stepRevision=\(stepRevision) surfaceReady=\(isSurfaceReady(step))"
        )

        schedulePreparationTimeout()
        issueNavigationOnceIfNeeded()
        issueScrollIfNeeded()

        if step.role == .tradingRulesPrompt, isSurfaceReady(step) {
            tryCommitPresentation(frame: .zero, revision: stepRevision)
        }
    }

    private func tryCommitPresentation(frame: CGRect, revision: UInt64) {
        ContextualTourDebug.logTourTrace(
            "tryCommitPresentation frame=\(frame) revision=\(revision) stepRevision=\(stepRevision) phase=\(phase) target=\(spotlightTarget?.debugLabel ?? "none") viewport=\(lastViewport?.debugDescription ?? "nil")"
        )
        guard revision == stepRevision, phase == .preparing, let step = currentStep else {
            ContextualTourDebug.logTourTrace(
                "tryCommitPresentation rejected revision=\(revision) stepRevision=\(stepRevision) phase=\(phase) hasStep=\(currentStep != nil)"
            )
            return
        }

        switch step.role {
        case .spotlight:
            if !(step.presentsIfUnmeasured && frame == .zero) {
                guard let viewport = lastViewport,
                      ContextualTourGeometry.isRenderableSpotlight(
                        frame,
                        in: ContextualTourGeometry.spotlightMeasurementVisibleRect(
                            viewport: viewport,
                            topInset: lastTopInset,
                            bottomInset: lastBottomInset,
                            target: step.target
                        )
                      )
                else {
                    ContextualTourDebug.logTourTrace("tryCommitPresentation rejected spotlight-not-renderable")
                    return
                }
            }
        case .narration:
            guard ContextualTourGeometry.isUsable(frame),
                  let viewport = lastViewport,
                  ContextualTourGeometry.isRenderableSpotlight(frame, in: viewport)
            else {
                ContextualTourDebug.logTourTrace("tryCommitPresentation rejected narration-not-renderable")
                return
            }
        case .finish, .tradingRulesPrompt, .sectionContinue:
            break
        }

        guard canPresent(step: step, frame: frame) else {
            let reason = "commit-blocked step=\(stepIndex)"
            ContextualTourDebug.logMeasureReject(reason)
            ContextualTourDebug.logTourTrace("tryCommitPresentation rejected \(reason)")
            return
        }

        spotlightFrame = frame
        scrollTarget = nil
        presentedStepRevision = revision
        cancelPreparationTimeout()
        navigationRequest = nil
        phase = .presenting
        ContextualTourDebug.logPhaseTransition("preparing", "presenting", "step=\(stepIndex) target=\(step.target?.debugLabel ?? "none")")
        ContextualTourDebug.logTourTrace(
            "phase transition preparing -> presenting session=\(sessionID) showsOverlay=\(showsOverlay) canShowBlockingChrome=\(canShowBlockingChrome)",
            force: true
        )
        ContextualTourDebug.logAppTour("presenting")
    }

    private func canPresent(step: ContextualTourStep, frame: CGRect) -> Bool {
        switch step.role {
        case .spotlight, .narration:
            if step.presentsIfUnmeasured, frame == .zero {
                return true
            }
            return ContextualTourGeometry.isUsable(frame)
        case .finish, .tradingRulesPrompt:
            return true
        case .sectionContinue:
            return false
        }
    }

    private func handlePreparingShellUpdate() {
        guard let step = currentStep else {
            ContextualTourDebug.logTourTrace("handlePreparingShellUpdate no-step -> cancel")
            cancelSession()
            return
        }
        if !isSurfaceReady(step) {
            ContextualTourDebug.logPhaseTransition("preparing", "idle", "user-left-destination")
            ContextualTourDebug.logTourTrace("session cancel reason=user-left-destination-during-preparing")
            cancelSession()
            return
        }
        issueNavigationOnceIfNeeded()
        issueScrollIfNeeded()
    }

    private func handlePresentingShellUpdate() {
        guard let step = currentStep else {
            ContextualTourDebug.logTourTrace("presenting shell update rejected no-step -> cancel")
            cancelSession()
            return
        }
        if !isSurfaceReady(step) {
            ContextualTourDebug.logPhaseTransition("presenting", "idle", "user-left-destination")
            ContextualTourDebug.logTourTrace("session cancel reason=user-left-destination-during-presenting")
            cancelSession()
        }
    }

    private func issueNavigationOnceIfNeeded() {
        guard phase == .preparing, let step = currentStep else {
            ContextualTourDebug.logTourTrace("issueNavigation rejected phase=\(phase)")
            return
        }
        if isSurfaceReady(step) {
            ContextualTourDebug.logTourTrace("issueNavigation skipped surface already ready step=\(stepIndex)")
            navigationRequest = nil
            navigationSatisfiedForStepIndex = stepIndex
            return
        }
        if navigationSatisfiedForStepIndex == stepIndex {
            ContextualTourDebug.logTourTrace("issueNavigation skipped already-issued step=\(stepIndex)")
            return
        }
        guard navigationRequest == nil else {
            ContextualTourDebug.logTourTrace("issueNavigation skipped request-in-flight \(navigationRequest?.rawValue ?? "")")
            return
        }
        navigationRequest = step.surface
        navigationSatisfiedForStepIndex = stepIndex
        ContextualTourDebug.logTourTrace("navigation-request issued-once surface=\(step.surface) step=\(stepIndex)")
        ContextualTourDebug.logAppTour("nav-once surface=\(step.surface)")
    }

    private func issueScrollIfNeeded() {
        // Autoscroll is driven from `noteMeasuredFrame` when the resolved target is not yet renderable.
    }

    private func issueScroll() {
        scrollIssuedForStepIndex = stepIndex
        scrollGeneration &+= 1
        scrollTarget = spotlightTarget
    }

    private func isSurfaceReady(_ step: ContextualTourStep) -> Bool {
        guard gates.sceneActive, gates.unobstructed else { return false }
        switch step.surface {
        case .dashboard:
            return gates.homeRootActive
        case .feed:
            return gates.feedRootActive
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

    private func acknowledge() {
        let persist = persistDismissalOnAcknowledge
        let completedUserID = persist ? userID : nil
        if let userID, persist {
            progress.dismiss(definition.id, version: definition.version, userID: userID)
            ContextualTourDebug.logAppTour("completed")
            PostAuthOnboardingProgress.markWalkthroughFinished(for: ProfileID(userID))
            NativeIosOnboardingSync.recordTourDismissed(
                userID: userID,
                version: definition.version,
                rpc: NativeIosOnboardingServices.rpc
            )
        }
        terminateSession(reason: "acknowledge")
        if let completedUserID {
            NotificationCenter.default.post(
                name: .contextualTourDidComplete,
                object: completedUserID
            )
        }
    }

    private func cancelSession() {
        ContextualTourDebug.logTourTrace("cancelSession invoked phase=\(phase) step=\(stepIndex)")
        blocksAutomaticRestart = true
        terminateSession(reason: "cancelled")
    }

    private func terminateSession(reason: String, resetStep: Bool = true) {
        cancelPreparationTimeout()
        let previous = phase
        if previous != .idle {
            ContextualTourDebug.logPhaseTransition("\(previous)", "idle", reason)
            ContextualTourDebug.logTourTrace("session terminated reason=\(reason) from=\(previous) resetStep=\(resetStep)")
        }
        phase = .idle
        activation = nil
        navigationRequest = nil
        spotlightFrame = .zero
        scrollTarget = nil
        stabilityCandidateFrame = nil
        presentingStabilityFrame = nil
        navigationSatisfiedForStepIndex = nil
        scrollIssuedForStepIndex = nil
        profileIdentityHeaderHydrated = false
        stepRevision &+= 1
        presentedStepRevision = 0
        ContextualTourGlobalFrameStore.shared.reset()
        if resetStep {
            stepIndex = 0
        }
    }

    private func schedulePreparationTimeout() {
        guard schedulesAsyncResolution else { return }
        preparationTimeoutGeneration &+= 1
        let generation = preparationTimeoutGeneration
        let sid = sessionID
        let stepAtStart = stepIndex
        let target = spotlightTarget
        let timeout = ContextualTourGeometry.resolveTimeout(for: target) + 0.25
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard generation == preparationTimeoutGeneration else { return }
            guard phase == .preparing, sessionID == sid, stepIndex == stepAtStart else {
                ContextualTourDebug.logTourTrace("preparation-timeout fired but obsolete gen=\(generation) phase=\(phase)")
                return
            }
            ContextualTourDebug.logTourTrace("preparation-timeout step=\(stepIndex) session=\(sid) target=\(target?.debugLabel ?? "none")")
            ContextualTourDebug.logAppTour("preparation-timeout step=\(stepIndex)")
            if let step = currentStep,
               step.target == .settingsTradingRules,
               step.presentsIfUnmeasured
            {
                tryCommitPresentation(frame: .zero, revision: stepRevision)
                return
            }
            blocksAutomaticRestart = true
            terminateSession(reason: "preparation-timeout")
        }
    }

    private func cancelPreparationTimeout() {
        preparationTimeoutGeneration &+= 1
    }

    private func progressPosition(for stepIndex: Int) -> (index: Int, total: Int)? {
        let indexed = definition.steps.enumerated().filter { $0.element.role.countsTowardProgress }
        let total = indexed.count
        guard total > 0 else { return nil }
        guard let match = indexed.firstIndex(where: { $0.offset == stepIndex }) else { return nil }
        return (match, total)
    }
}