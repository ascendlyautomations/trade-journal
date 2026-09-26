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

    @Environment(\.themeColors) private var colors
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
            let resolved = target.flatMap { id in anchors[id].map { proxy[$0] } }
            let liveHole = resolved.flatMap { frame in
                ContextualTourGeometry.isRenderableSpotlight(frame, in: viewport) ? frame : nil
            }
            let retainedHole = ContextualTourGeometry.isRenderableSpotlight(coordinator.spotlightFrame, in: viewport)
                ? coordinator.spotlightFrame
                : nil
            let holeFrame = liveHole ?? (coordinator.phase == .measuring ? retainedHole : nil)
            let hole = holeFrame.map { spotlightHole(around: $0, in: viewport) } ?? .zero
            let topInset = proxy.safeAreaInsets.top + ExperienceSpacing.sm
            let bottomInset = bottomChrome(safeBottom: proxy.safeAreaInsets.bottom)
            let showsChrome = coordinator.showsOverlay
            let showsExplanationCard = coordinator.showsExplanationCard
            let showsHole = hole.width > 1 && hole.height > 1 && showsChrome
            let canLock = coordinator.phase == .presenting && coordinator.showsExplanationCard
                && (coordinator.spotlightTarget == nil || showsHole)
            let stepKey = ContextualTourCardPlacement.stepKey(
                stepIndex: coordinator.visibleStepIndex,
                role: coordinator.visibleStep?.role ?? .spotlight
            )
            let proposedTop = ContextualTourCardPlacement.proposedTop(
                hole: showsHole ? hole : nil,
                cardHeight: cardHeight,
                containerSize: proxy.size,
                statusBarInset: proxy.safeAreaInsets.top,
                bottomInset: bottomInset
            )
            let cardTop = lockedStepKey == stepKey ? lockedCardTop : proposedTop
            let lockToken = ContextualTourCardLock(
                stepKey: stepKey,
                canLock: canLock,
                proposedTop: proposedTop
            )

            ZStack(alignment: .topLeading) {
                if showsChrome && !showsHole {
                    Color.black.opacity(0.55)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .accessibilityHidden(true)
                }
                if showsHole {
                    spotlight(hole: hole, size: proxy.size)
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
                        ContextualTourDebug.logMarker("overlay rendering")
                        if coordinator.visibleStep?.target == .dashboardAccountAndDates {
                            ContextualTourDebug.logMarker("Dashboard Step 1 visible")
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .allowsHitTesting(showsChrome)
            .onChange(of: resolved, initial: true) { _, frame in
                guard coordinator.phase == .measuring || coordinator.phase == .presenting else { return }
                let accepted = frame.flatMap { candidate in
                    ContextualTourGeometry.isMeasurableTarget(candidate, in: viewport) ? candidate : nil
                }
                coordinator.noteMeasuredFrame(
                    accepted,
                    viewport: viewport,
                    topInset: topInset,
                    bottomInset: bottomInset
                )
            }
            .onChange(of: lockToken, initial: true) { _, token in
                guard token.canLock, lockedStepKey != token.stepKey else { return }
                lockedCardTop = token.proposedTop
                lockedStepKey = token.stepKey
            }
            .onChange(of: coordinator.showsOverlay) { _, showing in
                if !showing {
                    lockedStepKey = ""
                }
            }
            .onChange(of: coordinator.stepIndex) { _, _ in
                cardFocused = coordinator.showsOverlay
            }
            .onChange(of: coordinator.showsOverlay) { _, showing in
                if showing {
                    cardFocused = true
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(!coordinator.showsOverlay)
    }

    private func cardWidth(in container: CGSize) -> CGFloat {
        min(360, max(0, container.width - ExperienceSpacing.lg * 2))
    }

    private func bottomChrome(safeBottom: CGFloat) -> CGFloat {
        if safeBottom >= 49 {
            return safeBottom + ExperienceSpacing.xs
        }
        return safeBottom + 49 + ExperienceSpacing.xs
    }

    /// Padding around the live target, clipped to this overlay's coordinate space.
    private func spotlightHole(around frame: CGRect, in viewport: CGRect) -> CGRect {
        let padded = frame.insetBy(dx: -ExperienceSpacing.xs, dy: -ExperienceSpacing.xs)
        let visible = viewport.insetBy(dx: 1, dy: 1)
        let hole = padded.intersection(visible)
        return hole.isNull ? .zero : hole
    }

    private func spotlight(hole: CGRect, size: CGSize) -> some View {
        ContextualTourSpotlightShape(hole: hole, cornerRadius: ExperienceRadius.md)
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .animation(
                reduceMotion ? nil : ContextualTourMotion.spotlightAnimation(reduceMotion: false),
                value: hole
            )
            .id(reduceMotion ? coordinator.stepIndex : 0)
            .transition(reduceMotion ? .opacity : .identity)
            .animation(
                reduceMotion ? .easeInOut(duration: MotionDuration.fast.value) : nil,
                value: coordinator.stepIndex
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
                HStack(spacing: ExperienceSpacing.sm) {
                    if step.role != .finish {
                        ExperienceButton(
                            title: step.role == .sectionContinue ? "Exit Tour" : "Exit",
                            kind: .text,
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

    private func primaryTitle(for step: ContextualTourStep) -> String {
        switch step.role {
        case .sectionContinue: return "Continue"
        case .finish: return "Finish"
        case .spotlight, .narration: return "Next"
        }
    }

    private func primaryIdentifier(for step: ContextualTourStep) -> String {
        switch step.role {
        case .sectionContinue: return "contextualTour.continue"
        case .finish: return "contextualTour.finish"
        case .spotlight, .narration: return "contextualTour.next"
        }
    }
}

private struct ContextualTourCardLock: Equatable {
    var stepKey: String
    var canLock: Bool
    var proposedTop: CGFloat
}

enum ContextualTourCardPlacement {
    static let gap = ExperienceSpacing.sm
    static let navigationClearance: CGFloat = 44
    static let minCardHeightEstimate: CGFloat = 168

    static func stepKey(stepIndex: Int, role: ContextualTourStepRole) -> String {
        "step-\(stepIndex)-\(role)"
    }

    /// Prefer directly below the spotlight; above if below does not fit; clamp within safe bounds.
    static func proposedTop(
        hole: CGRect?,
        cardHeight: CGFloat,
        containerSize: CGSize,
        statusBarInset: CGFloat,
        bottomInset: CGFloat
    ) -> CGFloat {
        let effectiveHeight = max(cardHeight, minCardHeightEstimate)
        let minTop = statusBarInset + navigationClearance + ExperienceSpacing.xs
        let maxTop = max(minTop, containerSize.height - bottomInset - effectiveHeight)

        guard let hole, hole.width > 1, hole.height > 1 else {
            return minTop + (maxTop - minTop) / 2
        }

        let belowTop = hole.maxY + gap
        if belowTop <= maxTop {
            return min(max(belowTop, minTop), maxTop)
        }

        let aboveTop = hole.minY - gap - effectiveHeight
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
