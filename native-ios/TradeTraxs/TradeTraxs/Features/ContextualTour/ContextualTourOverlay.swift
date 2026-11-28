import SwiftUI

struct ContextualTourAnchorKey: PreferenceKey {
    static var defaultValue: [ContextualTourTargetID: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [ContextualTourTargetID: Anchor<CGRect>],
        nextValue: () -> [ContextualTourTargetID: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct ContextualTourShellInput: Equatable {
    var userID: String?
    var accountCreatedAt: Date?
    var gates: ContextualTourGates
}

extension View {
    /// Marks a real control as a tour target. Adds no layout when that target is inactive.
    func contextualTourTarget(_ target: ContextualTourTargetID) -> some View {
        modifier(ContextualTourTargetModifier(target: target))
    }

    /// Hosts the single authenticated-shell tour overlay.
    func contextualTourHost(_ input: ContextualTourShellInput) -> some View {
        modifier(ContextualTourHostModifier(input: input))
    }
}

private struct ContextualTourTargetModifier: ViewModifier {
    let target: ContextualTourTargetID

    func body(content: Content) -> some View {
        content
            .id(target)
            .background {
                if ContextualTourCoordinator.shared.measures(target) {
                    Color.clear
                        .anchorPreference(key: ContextualTourAnchorKey.self, value: .bounds) { anchor in
                            [target: anchor]
                        }
                }
            }
    }
}

private struct ContextualTourHostModifier: ViewModifier {
    let input: ContextualTourShellInput

    private var coordinator: ContextualTourCoordinator { .shared }

    func body(content: Content) -> some View {
        let exitNotice = coordinator.exitNotice
        content
            .overlayPreferenceValue(ContextualTourAnchorKey.self) { anchors in
                ContextualTourOverlay(anchors: anchors)
            }
            .onAppear {
                ContextualTourDebug.logTourTrace("overlay host mounted")
                ContextualTourCoordinator.shared.syncShell(
                    userID: input.userID,
                    createdAt: input.accountCreatedAt,
                    gates: input.gates
                )
            }
            .onChange(of: input) { _, newValue in
                ContextualTourCoordinator.shared.syncShell(
                    userID: newValue.userID,
                    createdAt: newValue.accountCreatedAt,
                    gates: newValue.gates
                )
            }
            .alert(
                "App Walkthrough",
                isPresented: Binding(
                    get: { coordinator.exitNotice != nil },
                    set: { showing in
                        if !showing {
                            coordinator.clearExitNotice()
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exitNotice ?? "")
            }
    }
}

private struct ContextualTourCardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ContextualTourOverlay: View {
    let anchors: [ContextualTourTargetID: Anchor<CGRect>]

    @Bindable private var globalFrames = ContextualTourGlobalFrameStore.shared
    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var cardFocused: Bool
    @State private var cardHeight: CGFloat = 0
    /// Top edge is chosen once per explanation step. Later anchor drift does not move the card.
    @State private var lockedStepKey = ""
    @State private var lockedCardTop: CGFloat = 0

    private var coordinator: ContextualTourCoordinator { .shared }

    var body: some View {
        GeometryReader { proxy in
            let viewport = CGRect(origin: .zero, size: proxy.size)
            let target = coordinator.spotlightTarget
            let resolved = resolvedTargetFrame(
                target: target,
                anchors: anchors,
                proxy: proxy,
                viewport: viewport
            )
            let _ = globalFrames.reportGeneration
            let overlayMeasurement = ContextualTourOverlayMeasurement(
                revision: coordinator.stepRevision,
                target: target,
                frame: resolved
            )
            let retainedHole =
                coordinator.phase == .presenting
                && ContextualTourGeometry.isRenderableSpotlight(coordinator.spotlightFrame, in: viewport)
                ? ContextualTourGeometry.refinedSpotlightFrame(coordinator.spotlightFrame, for: target)
                : nil
            let hole = retainedHole.map { spotlightHole(around: $0, in: viewport) } ?? .zero
            let scrimOpacity = ContextualTourGeometry.spotlightScrimOpacity(colorScheme: colorScheme)
            let topInset = proxy.safeAreaInsets.top
                + ExperienceSpacing.sm
                + ContextualTourGeometry.measurementTopInset(for: target)
            let bottomInset = bottomChrome(
                safeBottom: proxy.safeAreaInsets.bottom,
                target: target
            )
            let showsChrome = coordinator.showsOverlay
            let showsHole = hole.width > 1 && hole.height > 1 && showsChrome
            let showsExplanationCard = coordinator.showsExplanationCard && showsChrome
            let canLock = showsExplanationCard
                && (
                    coordinator.visibleStep?.role == .tradingRulesPrompt
                        || coordinator.visibleStep?.presentsIfUnmeasured == true && !showsHole
                        || coordinator.spotlightTarget == nil
                        || showsHole
                )
            let stepKey = ContextualTourCardPlacement.stepKey(
                stepIndex: coordinator.visibleStepIndex,
                role: coordinator.visibleStep?.role ?? .spotlight
            )
            let proposedTop =
                target?.isMainTabBarTarget == true
                ? ContextualTourCardPlacement.proposedTopForMainTab(
                    target: target,
                    cardHeight: cardHeight,
                    containerSize: proxy.size,
                    statusBarInset: proxy.safeAreaInsets.top,
                    bottomInset: bottomInset
                )
                : ContextualTourCardPlacement.proposedTop(
                    hole: showsHole ? hole : nil,
                    cardHeight: cardHeight,
                    containerSize: proxy.size,
                    statusBarInset: proxy.safeAreaInsets.top,
                    bottomInset: bottomInset,
                    preferAboveHole: target?.prefersWalkthroughCardAboveSpotlight ?? false,
                    target: target
                )
            let cardTop = resolvedExplanationCardTop(
                target: target,
                stepKey: stepKey,
                proposedTop: proposedTop,
                cardHeight: cardHeight
            )
            let lockToken = ContextualTourCardLock(
                stepKey: stepKey,
                canLock: canLock,
                proposedTop: proposedTop
            )

            ZStack(alignment: .topLeading) {
                if showsChrome, !showsHole, showsExplanationCard {
                    Color.black.opacity(scrimOpacity)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .accessibilityHidden(true)
                }
                if showsHole {
                    spotlight(hole: hole, size: proxy.size, scrimOpacity: scrimOpacity)
                        .transaction { transaction in
                            if coordinator.phase == .presenting {
                                transaction.animation = nil
                            }
                        }
                }
                if showsExplanationCard, let step = coordinator.visibleStep {
                    explanationCard(
                        step: step,
                        width: cardWidth(in: proxy.size),
                        maxHeight: max(1, proxy.size.height - bottomInset - cardTop)
                    )
                    .padding(.top, cardTop)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                    .onAppear {
                        ContextualTourDebug.logTourTrace(
                            "explanation card onAppear step=\(coordinator.visibleStepIndex) title=\(step.title) showsOverlay=\(coordinator.showsOverlay)"
                        )
                        ContextualTourDebug.logMarker("overlay rendering")
                        if coordinator.visibleStep?.target == .dashboardAccountAndDates {
                            ContextualTourDebug.logMarker("Dashboard Step 1 visible")
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .allowsHitTesting(showsChrome)
            .onChange(of: overlayMeasurement, initial: true) { _, measurement in
                deliverOverlayMeasurement(
                    measurement: measurement,
                    viewport: viewport,
                    topInset: topInset,
                    bottomInset: bottomInset
                )
            }
            .onChange(of: globalFrames.reportGeneration) { _, _ in
                deliverOverlayMeasurement(
                    measurement: overlayMeasurement,
                    viewport: viewport,
                    topInset: topInset,
                    bottomInset: bottomInset
                )
            }
            .onChange(of: lockToken, initial: true) { _, token in
                let isProfileIdentity = coordinator.spotlightTarget == .profileIdentity
                let mayLock =
                    token.canLock
                    || (
                        isProfileIdentity
                            && coordinator.phase == .presenting
                            && showsExplanationCard
                            && showsHole
                    )
                guard mayLock, lockedStepKey != token.stepKey else { return }
                lockedCardTop = token.proposedTop
                lockedStepKey = token.stepKey
            }
            .onChange(of: coordinator.showsOverlay) { _, showing in
                if !showing {
                    lockedStepKey = ""
                }
            }
            .onChange(of: coordinator.stepRevision) { _, _ in
                lockedStepKey = ""
                cardFocused = coordinator.showsOverlay
            }
            .onChange(of: coordinator.showsOverlay) { _, showing in
                ContextualTourDebug.logTourTrace(
                    "showsOverlay=\(showing) phase=\(coordinator.phase) showsExplanationCard=\(coordinator.showsExplanationCard)"
                )
                if showing {
                    cardFocused = true
                }
            }
        }
        .allowsHitTesting(coordinator.showsOverlay)
        .ignoresSafeArea()
        .accessibilityHidden(!coordinator.showsOverlay)
    }

    private func resolvedTargetFrame(
        target: ContextualTourTargetID?,
        anchors: [ContextualTourTargetID: Anchor<CGRect>],
        proxy: GeometryProxy,
        viewport: CGRect
    ) -> CGRect? {
        guard let target else { return nil }
        if ContextualTourTargetCatalog.globalMeasuredTargets.contains(target),
           coordinator.acceptsGlobalMeasurement(for: target),
           let global = globalFrames.frames[target]
        {
            let local = globalFrameInOverlay(global: global, proxy: proxy)
            if let refined = measurableRefinedFrame(local, in: viewport, target: target) {
                return refined
            }
        }
        if let anchor = anchors[target] {
            let local = proxy[anchor]
            if let refined = measurableRefinedFrame(local, in: viewport, target: target) {
                return refined
            }
        }
        if coordinator.acceptsGlobalMeasurement(for: target),
           let global = globalFrames.frames[target]
        {
            let local = globalFrameInOverlay(global: global, proxy: proxy)
            if let refined = measurableRefinedFrame(local, in: viewport, target: target) {
                return refined
            }
        }
        return nil
    }

    private func measurableRefinedFrame(
        _ local: CGRect,
        in viewport: CGRect,
        target: ContextualTourTargetID
    ) -> CGRect? {
        guard ContextualTourGeometry.isMeasurableTarget(local, in: viewport) else { return nil }
        return ContextualTourGeometry.refinedSpotlightFrame(local, for: target)
    }

    /// Card top is locked for most steps; main tabs and feed filters follow live layout so placement tweaks apply.
    private func resolvedExplanationCardTop(
        target: ContextualTourTargetID?,
        stepKey: String,
        proposedTop: CGFloat,
        cardHeight: CGFloat
    ) -> CGFloat {
        if target == .profileIdentity,
           coordinator.phase == .presenting,
           lockedStepKey == stepKey
        {
            return lockedCardTop
        }
        let usesLivePlacement =
            target?.isMainTabBarTarget == true || target == .feedContentFilters
        if target == .mainTabHome, cardHeight > 1 {
            let effectiveHeight = max(cardHeight, ContextualTourCardPlacement.minCardHeightEstimate)
            ContextualTourCardPlacement.mainTabHomeRenderedCardBottom = proposedTop + effectiveHeight
        }
        if usesLivePlacement {
            return proposedTop
        }
        return lockedStepKey == stepKey ? lockedCardTop : proposedTop
    }

    private func globalFrameInOverlay(global: CGRect, proxy: GeometryProxy) -> CGRect {
        let origin = proxy.frame(in: .global).origin
        return CGRect(
            x: global.minX - origin.x,
            y: global.minY - origin.y,
            width: global.width,
            height: global.height
        )
    }

    private func cardWidth(in container: CGSize) -> CGFloat {
        min(360, max(0, container.width - ExperienceSpacing.lg * 2))
    }

  private func deliverOverlayMeasurement(
    measurement: ContextualTourOverlayMeasurement,
    viewport: CGRect,
    topInset: CGFloat,
    bottomInset: CGFloat
  ) {
    let target = measurement.target
    let accepted: CGRect? = {
      guard let candidate = measurement.frame else {
        ContextualTourDebug.logTourTrace(
          "overlay measurement resolved=nil target=\(target?.debugLabel ?? "none") phase=\(coordinator.phase)"
        )
        return nil
      }
      guard ContextualTourGeometry.isMeasurableTarget(candidate, in: viewport) else {
        ContextualTourDebug.logTourTrace(
          "overlay measurement rejected not-measurable target=\(target?.debugLabel ?? "none") local=\(candidate) viewport=\(viewport)"
        )
        return nil
      }
      if target == .mainTabHome {
        ContextualTourDebug.logTourTrace(
          "overlay mainTabHome local=\(candidate) viewport=\(viewport) globalInStore=\(globalFrames.frames[.mainTabHome]?.debugDescription ?? "nil")"
        )
      }
      return candidate
    }()
    let revision = measurement.revision
    ContextualTourDebug.logTourTrace(
      "overlay forwards measurement phase=\(coordinator.phase) accepted=\(accepted?.debugDescription ?? "nil") revision=\(revision)"
    )
#if DEBUG
    if target == .feedContentFilters, let accepted {
      ContextualTourDebug.log(
        "feedFilters overlay resolved=\(accepted) holeWillUse=\(coordinator.spotlightFrame)"
      )
    }
#endif
    switch coordinator.phase {
    case .preparing:
      coordinator.noteMeasuredFrame(
        accepted,
        viewport: viewport,
        topInset: topInset,
        bottomInset: bottomInset,
        revision: revision
      )
    case .presenting:
      coordinator.notePresentingLayoutFrame(
        accepted,
        viewport: viewport,
        topInset: topInset,
        bottomInset: bottomInset,
        revision: coordinator.presentedStepRevision
      )
    case .idle:
      ContextualTourDebug.logTourTrace("overlay measurement ignored phase=idle")
    }
  }

    private func bottomChrome(safeBottom: CGFloat, target: ContextualTourTargetID?) -> CGFloat {
        let tabReserve: CGFloat
        if safeBottom >= 49 {
            tabReserve = safeBottom + ExperienceSpacing.xs
        } else {
            tabReserve = safeBottom + 49 + ExperienceSpacing.xs
        }
        return tabReserve + ContextualTourGeometry.measurementBottomInset(for: target)
    }

    /// Padding around the live target, clipped to this overlay's coordinate space.
    private func spotlightHole(around frame: CGRect, in viewport: CGRect) -> CGRect {
        let padding = ContextualTourGeometry.spotlightHolePadding(for: coordinator.spotlightTarget)
        let padded = frame.insetBy(dx: -padding.horizontal, dy: -padding.vertical)
        let visible = viewport.insetBy(dx: 1, dy: 1)
        let hole = padded.intersection(visible)
        return hole.isNull ? .zero : hole
    }

    private func spotlight(hole: CGRect, size: CGSize, scrimOpacity: CGFloat) -> some View {
        let cornerRadius = ExperienceRadius.md
        return ZStack(alignment: .topLeading) {
            ContextualTourSpotlightShape(hole: hole, cornerRadius: cornerRadius)
                .fill(Color.black.opacity(scrimOpacity), style: FillStyle(eoFill: true))
            if colorScheme == .dark, hole.width > 1, hole.height > 1 {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(colors.primaryText.opacity(0.38), lineWidth: 1)
                    .frame(width: hole.width, height: hole.height)
                    .offset(x: hole.minX, y: hole.minY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .animation(nil, value: hole)
        .id(reduceMotion ? coordinator.stepRevision : 0)
        .transition(reduceMotion ? .opacity : .identity)
        .animation(
            reduceMotion ? .easeInOut(duration: MotionDuration.fast.value) : nil,
            value: coordinator.stepRevision
        )
        .accessibilityHidden(true)
    }

    /// Content height, capped only when Dynamic Type no longer fits. `.position` lays this out at that size.
    private func explanationCard(step: ContextualTourStep, width: CGFloat, maxHeight: CGFloat) -> some View {
        ViewThatFits(in: .vertical) {
            cardBody(step: step)
            ScrollView {
                cardBody(step: step)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: maxHeight, alignment: .top)
        }
        .frame(width: width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { cardProxy in
                Color.clear.preference(key: ContextualTourCardHeightKey.self, value: cardProxy.size.height)
            }
        }
        .onPreferenceChange(ContextualTourCardHeightKey.self) { cardHeight = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("contextualTour.card")
    }

    private func cardBody(step: ContextualTourStep) -> some View {
        ExperienceCard(elevated: true) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Text(step.title)
                    .experienceStyle(.headline, color: colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($cardFocused)
                Text(step.message)
                    .experienceStyle(.subheadline, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if !coordinator.progressLabel.isEmpty {
                    Text(coordinator.progressLabel)
                        .experienceStyle(.caption, color: colors.tertiaryText)
                        .accessibilityLabel("Step \(coordinator.progressLabel)")
                }
                if step.role == .tradingRulesPrompt {
                    HStack(spacing: ExperienceSpacing.sm) {
                        ExperienceButton(
                            title: "Maybe Later",
                            kind: .secondary,
                            accessibilityIdentifier: "contextualTour.tradingRules.later"
                        ) {
                            coordinator.completeTour(configureTradingRules: false)
                        }
                        ExperienceButton(
                            title: "Configure Now",
                            kind: .primary,
                            accessibilityIdentifier: "contextualTour.tradingRules.configure"
                        ) {
                            coordinator.completeTour(configureTradingRules: true)
                        }
                    }
                } else {
                    HStack(spacing: ExperienceSpacing.sm) {
                        if step.role != .finish {
                            ExperienceButton(
                                title: step.role == .sectionContinue ? "Exit Tour" : "Exit",
                                kind: .secondary,
                                accessibilityIdentifier: "contextualTour.exit"
                            ) {
                                coordinator.exitTour()
                            }
                        }
                        ExperienceButton(
                            title: primaryTitle(for: step),
                            kind: .primary,
                            accessibilityIdentifier: primaryIdentifier(for: step)
                        ) {
                            coordinator.advance()
                        }
                    }
                }
            }
        }
    }

    private func primaryTitle(for step: ContextualTourStep) -> String {
        switch step.role {
        case .sectionContinue: return "Continue"
        case .finish: return "Finish"
        case .tradingRulesPrompt: return "Finish"
        case .spotlight, .narration: return "Next"
        }
    }

    private func primaryIdentifier(for step: ContextualTourStep) -> String {
        switch step.role {
        case .sectionContinue: return "contextualTour.continue"
        case .finish: return "contextualTour.finish"
        case .tradingRulesPrompt: return "contextualTour.finish"
        case .spotlight, .narration: return "contextualTour.next"
        }
    }
}

private struct ContextualTourCardLock: Equatable {
    var stepKey: String
    var canLock: Bool
    var proposedTop: CGFloat
}

/// Stable, equatable snapshot of a resolved spotlight frame for `onChange` (optional `CGRect` is awkward for inference).
private struct ContextualTourOverlayMeasurement: Equatable {
    var revision: UInt64
    var target: ContextualTourTargetID?
    var minX: CGFloat
    var minY: CGFloat
    var width: CGFloat
    var height: CGFloat

    init(revision: UInt64, target: ContextualTourTargetID?, frame: CGRect?) {
        self.revision = revision
        self.target = target
        if let frame, ContextualTourGeometry.isUsable(frame) {
            minX = frame.minX
            minY = frame.minY
            width = frame.width
            height = frame.height
        } else {
            minX = 0
            minY = 0
            width = 0
            height = 0
        }
    }

    var frame: CGRect? {
        guard ContextualTourGeometry.isUsable(
            CGRect(x: minX, y: minY, width: width, height: height)
        ) else {
            return nil
        }
        return CGRect(x: minX, y: minY, width: width, height: height)
    }
}

enum ContextualTourCardPlacement {
    static let gap = ExperienceSpacing.sm
    static let navigationClearance: CGFloat = 44
    static let minCardHeightEstimate: CGFloat = 168
    /// Shared baseline for all main-tab walkthrough cards (matches Home tab positioning).
    static let mainTabCardLiftAboveChrome: CGFloat = ExperienceSpacing.lg + ExperienceSpacing.sm
    /// Bottom edge of the rendered Home tab explanation card (set while S1 is on screen).
    static var mainTabHomeRenderedCardBottom: CGFloat?

    static func stepKey(stepIndex: Int, role: ContextualTourStepRole) -> String {
        "step-\(stepIndex)-\(role)"
    }

    /// Prefer directly below the spotlight; above if below does not fit; clamp within safe bounds.
    /// Fixed vertical position for bottom-tab steps so every card sits comfortably above the tab bar.
    static func proposedTopForMainTab(
        target: ContextualTourTargetID?,
        cardHeight: CGFloat,
        containerSize: CGSize,
        statusBarInset: CGFloat,
        bottomInset: CGFloat
    ) -> CGFloat {
        let effectiveHeight = max(cardHeight, minCardHeightEstimate)
        let minTop = statusBarInset + navigationClearance + ExperienceSpacing.xs
        let maxTop = max(minTop, containerSize.height - bottomInset - effectiveHeight)

        if target == .mainTabFeed || target == .mainTabCreate,
           let referenceBottom = mainTabHomeRenderedCardBottom
        {
            let alignedTop = referenceBottom - effectiveHeight
            return min(max(alignedTop, minTop), maxTop)
        }

        let targetTop = containerSize.height - bottomInset - effectiveHeight - mainTabCardLiftAboveChrome
        return min(max(targetTop, minTop), maxTop)
    }

    static func proposedTop(
        hole: CGRect?,
        cardHeight: CGFloat,
        containerSize: CGSize,
        statusBarInset: CGFloat,
        bottomInset: CGFloat,
        preferAboveHole: Bool = false,
        target: ContextualTourTargetID? = nil
    ) -> CGFloat {
        let effectiveHeight = max(cardHeight, minCardHeightEstimate)
        let minTop = statusBarInset + navigationClearance + ExperienceSpacing.xs
        let maxTop = max(minTop, containerSize.height - bottomInset - effectiveHeight)

        guard let hole, hole.width > 1, hole.height > 1 else {
            return minTop + (maxTop - minTop) / 2
        }

        if target == .feedContentFilters || target == .dashboardGettingStarted {
            let belowTop = hole.maxY + gap + ExperienceSpacing.md
            return min(max(belowTop, minTop), maxTop)
        }

        let aboveTop = hole.minY - gap - effectiveHeight
        let belowTop = hole.maxY + gap

        if preferAboveHole, aboveTop >= minTop {
            return min(max(aboveTop, minTop), maxTop)
        }

        if belowTop <= maxTop {
            return min(max(belowTop, minTop), maxTop)
        }

        if aboveTop >= minTop {
            return min(max(aboveTop, minTop), maxTop)
        }

        return min(max(belowTop, minTop), maxTop)
    }
}

private struct ContextualTourSpotlightShape: Shape {
    var hole: CGRect
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(hole.origin.x, hole.origin.y),
                AnimatablePair(hole.size.width, hole.size.height)
            )
        }
        set {
            hole = CGRect(
                x: newValue.first.first,
                y: newValue.first.second,
                width: newValue.second.first,
                height: newValue.second.second
            )
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(
            in: hole,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
        )
        return path
    }
}
