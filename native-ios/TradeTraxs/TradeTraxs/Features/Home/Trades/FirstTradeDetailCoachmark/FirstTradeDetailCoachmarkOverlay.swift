import SwiftUI

struct FirstTradeDetailCoachmarkAnchorKey: PreferenceKey {
    static var defaultValue: [TradeID: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [TradeID: Anchor<CGRect>],
        nextValue: () -> [TradeID: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    func firstTradeDetailCoachmarkAnchor(for tradeID: TradeID) -> some View {
        modifier(FirstTradeDetailCoachmarkAnchorModifier(tradeID: tradeID))
    }

    func firstTradeDetailCoachmarkHost() -> some View {
        overlayPreferenceValue(FirstTradeDetailCoachmarkAnchorKey.self) { anchors in
            FirstTradeDetailCoachmarkOverlay(anchors: anchors)
        }
    }
}

private struct FirstTradeDetailCoachmarkAnchorModifier: ViewModifier {
    let tradeID: TradeID

    private var store: FirstTradeDetailCoachmarkStore { .shared }

    func body(content: Content) -> some View {
        content
            .background {
                if store.pendingTradeID == tradeID {
                    Color.clear
                        .anchorPreference(key: FirstTradeDetailCoachmarkAnchorKey.self, value: .bounds) { anchor in
                            [tradeID: anchor]
                        }
                }
            }
    }
}

private struct FirstTradeDetailCoachmarkOverlay: View {
    let anchors: [TradeID: Anchor<CGRect>]

    @Bindable private var store = FirstTradeDetailCoachmarkStore.shared
    @Bindable private var reflectionGate = PostTradeReflectionGate.shared
    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var previousFrame: CGRect?
    @State private var resolveStartedAt: Date?
    @State private var lockedHole: CGRect?
    @State private var lockedCardTop: CGFloat = 0
    @State private var cardHeight: CGFloat = 0
    @State private var showsSpotlight = false

    private var tourShowsOverlay: Bool {
        ContextualTourCoordinator.shared.showsOverlay
    }

    private var mayResolveAnchor: Bool {
        store.pendingTradeID != nil
            && reflectionGate.pendingTrade == nil
            && !tourShowsOverlay
    }

    var body: some View {
        GeometryReader { proxy in
            let viewport = CGRect(origin: .zero, size: proxy.size)
            let pendingID = store.pendingTradeID
            let resolved = pendingID.flatMap { id in anchors[id].map { proxy[$0] } }
            let liveRenderable = resolved.flatMap { frame in
                ContextualTourGeometry.isRenderableSpotlight(frame, in: viewport) ? frame : nil
            }
            let holeFrame: CGRect? = {
                if showsSpotlight, let lockedHole, ContextualTourGeometry.isRenderableSpotlight(lockedHole, in: viewport) {
                    return lockedHole
                }
                return liveRenderable
            }()
            let hole = holeFrame.map { spotlightHole(around: $0, in: viewport) } ?? .zero
            let showsHole = showsSpotlight && hole.width > 1 && hole.height > 1
            let bottomInset = bottomChrome(safeBottom: proxy.safeAreaInsets.bottom)
            let proposedTop = ContextualTourCardPlacement.proposedTop(
                hole: showsHole ? hole : nil,
                cardHeight: cardHeight,
                containerSize: proxy.size,
                statusBarInset: proxy.safeAreaInsets.top,
                bottomInset: bottomInset
            )
            let cardTop = showsSpotlight ? lockedCardTop : proposedTop

            ZStack(alignment: .topLeading) {
                if showsSpotlight && !showsHole {
                    Color.black.opacity(0.55)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .accessibilityHidden(true)
                }
                if showsHole {
                    FirstTradeDetailCoachmarkSpotlightShape(hole: hole, cornerRadius: ExperienceRadius.md)
                        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                        .accessibilityHidden(true)
                }
                if showsSpotlight {
                    coachmarkCard(width: cardWidth(in: proxy.size))
                        .padding(.top, cardTop)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .allowsHitTesting(showsSpotlight)
            .onChange(of: resolved, initial: true) { _, frame in
                guard mayResolveAnchor else {
                    resetMeasurement()
                    return
                }
                let accepted = frame.flatMap { candidate in
                    ContextualTourGeometry.isMeasurableTarget(candidate, in: viewport) ? candidate : nil
                }
                noteMeasuredFrame(accepted, viewport: viewport, proposedTop: proposedTop)
            }
            .onChange(of: mayResolveAnchor) { _, may in
                if !may {
                    resetMeasurement()
                }
            }
            .onChange(of: store.pendingTradeID) { _, pending in
                if pending == nil {
                    resetMeasurement()
                } else {
                    resolveStartedAt = Date()
                    previousFrame = nil
                    lockedHole = nil
                    showsSpotlight = false
                }
            }
            .onChange(of: reflectionGate.pendingTrade) { _, pending in
                if pending != nil {
                    resetMeasurement()
                }
            }
            .onChange(of: tourShowsOverlay) { _, tourActive in
                if tourActive {
                    resetMeasurement()
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(!showsSpotlight)
    }

    private func coachmarkCard(width: CGFloat) -> some View {
        ExperienceCard(elevated: true) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Text("View your trade")
                    .experienceStyle(.headline, color: colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Tap a trade to see your full trade details and deeper analytics.")
                    .experienceStyle(.subheadline, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ExperienceButton(
                    title: "Got it",
                    kind: .primary,
                    accessibilityIdentifier: "firstTradeDetailCoachmark.gotIt"
                ) {
                    store.dismissGotIt()
                }
            }
        }
        .frame(width: width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { cardProxy in
                Color.clear.preference(key: FirstTradeDetailCoachmarkCardHeightKey.self, value: cardProxy.size.height)
            }
        }
        .onPreferenceChange(FirstTradeDetailCoachmarkCardHeightKey.self) { cardHeight = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("firstTradeDetailCoachmark.card")
    }

    private func noteMeasuredFrame(_ frame: CGRect?, viewport: CGRect, proposedTop: CGFloat) {
        guard mayResolveAnchor else { return }

        guard let frame, ContextualTourGeometry.isUsable(frame) else {
            return
        }

        let started = resolveStartedAt ?? Date()
        if resolveStartedAt == nil {
            resolveStartedAt = started
        }
        let elapsed = Date().timeIntervalSince(started)

        switch ContextualTourGeometry.resolve(frame: frame, previous: previousFrame, elapsed: elapsed) {
        case .ready(let stable):
            lockedHole = stable
            lockedCardTop = proposedTop
            showsSpotlight = true
        case .waiting:
            previousFrame = frame
        case .skip:
            if ContextualTourGeometry.isUsable(frame) {
                lockedHole = frame
                lockedCardTop = proposedTop
                showsSpotlight = true
            } else {
                resetMeasurement()
            }
        }
    }

    private func resetMeasurement() {
        previousFrame = nil
        resolveStartedAt = nil
        lockedHole = nil
        showsSpotlight = false
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

    private func spotlightHole(around frame: CGRect, in viewport: CGRect) -> CGRect {
        let padded = frame.insetBy(dx: -ExperienceSpacing.xs, dy: -ExperienceSpacing.xs)
        let visible = viewport.insetBy(dx: 1, dy: 1)
        let hole = padded.intersection(visible)
        return hole.isNull ? .zero : hole
    }
}

private struct FirstTradeDetailCoachmarkCardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct FirstTradeDetailCoachmarkSpotlightShape: Shape {
    var hole: CGRect
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(
            in: hole,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
        )
        return path
    }
}
