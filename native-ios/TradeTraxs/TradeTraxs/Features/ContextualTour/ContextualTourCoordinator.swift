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
    /// Set when the next spotlight lives on another screen. The shell performs the navigation.
    private(set) var navigationRequest: ContextualTourSurface?
    /// Shown after Exit. Nil while the walkthrough is running.
    private(set) var exitNotice: String?

    private var userID: String?
    private var createdAt: Date?
    private var gates = ContextualTourGates()
    private var analyticsReady = false
    private var replayArmed = false
    /// Stops an exhausted pass from immediately re-arming until the user leaves Dashboard.
    private var suppressedUntilGatesDrop = false
    private var resolveStartedAt: Date?
    private var previousFrame: CGRect?
    private var scrollIssuedForStep: Int?
    private var measurementToken: UInt64 = 0
    private var timeoutTask: Task<Void, Never>?
    private var confirmationTask: Task<Void, Never>?
    /// Keeps the explanation card up while the next real target is scrolling into place.
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
        currentStep?.role == .finish
    }

    /// Full explanation card — hidden during cross-surface transitions and section prompts.
    var showsExplanationCard: Bool {
        phase == .presenting && (currentStep?.role.countsTowardProgress ?? false)
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
        case .sectionContinue, .finish:
            return nil
        }
    }

    var visibleStepIndex: Int {
        phase == .presenting ? stepIndex : displayedStepIndex
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

    func syncShell(userID: String?, createdAt: Date?, gates: ContextualTourGates) {
        if userID != self.userID {
            clearMemory()
        }
        self.userID = userID
        self.createdAt = createdAt
        self.gates = gates
        reevaluate()
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
        exitNotice = nil
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
            if let frame, ContextualTourGeometry.isRenderableSpotlight(frame, in: viewport) {
                spotlightFrame = frame
            }
            return
        }

        if let frame,
           ContextualTourGeometry.isUsable(frame),
           ContextualTourGeometry.needsScroll(
            frame: frame,
            viewport: viewport,
            topInset: topInset,
            bottomInset: bottomInset
           ) {
            if scrollIssuedForStep != stepIndex {
                issueScroll(now: now)
            }
            return
        }

        guard let frame, ContextualTourGeometry.isUsable(frame) else {
            return
        }

        let elapsed = now.timeIntervalSince(resolveStartedAt ?? now)
        switch ContextualTourGeometry.resolve(frame: frame, previous: previousFrame, elapsed: elapsed) {
        case .ready(let stable):
            presentResolvedStep(frame: stable)
        case .waiting, .skip:
            let needsConfirmation = previousFrame == nil
            previousFrame = frame
            if needsConfirmation {
                scheduleConfirmation(of: frame, viewport: viewport, topInset: topInset, bottomInset: bottomInset)
            }
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
        guard elapsed >= ContextualTourGeometry.resolveTimeout else { return }
        if let previousFrame, ContextualTourGeometry.isUsable(previousFrame) {
            presentResolvedStep(frame: previousFrame)
            return
        }
        if currentStep?.presentsIfUnmeasured == true {
            presentResolvedStep(frame: .zero)
            return
        }
        skipUnresolvedStep()
    }

    private func presentResolvedStep(frame: CGRect) {
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

        let dismissed = progress.dismissedVersion(for: definition.id, userID: userID)
        let automatic = ContextualTourEligibility.shouldAutomaticallyPresent(
            createdAt: createdAt,
            cutoff: cutoff,
            dismissedVersion: dismissed,
            tourVersion: definition.version
        )
        guard replayArmed || automatic else {
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
            return gates.homeRootActive && analyticsReady
        case .feed:
            return gates.feedRootActive
        case .profile:
            return gates.profileRootActive
        case .settings:
            return gates.settingsHomeActive
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
        scrollTarget = nil
        resolveStartedAt = Date()
        navigationRequest = isSurfaceReady(step) ? nil : step.surface
        if step.role != .spotlight {
            presentResolvedStep(frame: .zero)
            return
        }
        phase = .measuring
        scheduleTimeout()
    }

    private func issueScroll(now: Date) {
        scrollIssuedForStep = stepIndex
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
            try? await Task.sleep(nanoseconds: UInt64(ContextualTourGeometry.resolveTimeout * 1_000_000_000))
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
        stepIndex = next
        beginMeasuring()
    }

    private func acknowledge() {
        let persistDismissal = !replayArmed
        if let userID, persistDismissal {
            progress.dismiss(definition.id, version: definition.version, userID: userID)
            ContextualTourDebug.logAppTour("completed")
        }
        replayArmed = false
        suppressedUntilGatesDrop = true
        hideWithoutDismiss(resetStep: true)
    }

    private func finishWithoutDismiss() {
        suppressedUntilGatesDrop = true
        replayArmed = false
        hideWithoutDismiss(resetStep: true)
    }

    private func hideWithoutDismiss(resetStep: Bool) {
        timeoutTask?.cancel()
        confirmationTask?.cancel()
        measurementToken &+= 1
        phase = .idle
        scrollTarget = nil
        previousFrame = nil
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

    private func progressPosition(for stepIndex: Int) -> (index: Int, total: Int)? {
        let indexed = definition.steps.enumerated().filter { $0.element.role.countsTowardProgress }
        let total = indexed.count
        guard total > 0 else { return nil }
        guard let match = indexed.firstIndex(where: { $0.offset == stepIndex }) else { return nil }
        return (match, total)
    }
}
