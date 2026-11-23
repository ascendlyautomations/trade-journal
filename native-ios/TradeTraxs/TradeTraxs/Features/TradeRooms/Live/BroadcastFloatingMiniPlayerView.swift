import LiveKit
import SwiftUI
import UIKit

/// Draggable 16:9 floating livestream — tab-shell overlay (not safe-area inset).
struct BroadcastFloatingMiniPlayerOverlay: View {
    @Bindable var coordinator: RoomBroadcastCoordinator
    @Bindable private var tabBarMetrics = MainTabBarLayoutMetrics.shared

    @State private var dragTranslation: CGSize = .zero
    @State private var isDragging = false

    private let horizontalMargin: CGFloat = 12
    private let verticalMargin: CGFloat = 10
    private let cornerRadius: CGFloat = 12
    private let maxPlayerWidth: CGFloat = 200
    private let widthToScreenRatio: CGFloat = 0.44

    var body: some View {
        GeometryReader { proxy in
            if coordinator.showsFloatingMiniPlayer {
                let layout = layoutMetrics(in: proxy)
                miniPlayer(layout: layout)
                    .position(currentCenter(layout: layout))
                    .gesture(dragGesture(layout: layout))
                    .zIndex(900)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .accessibilityIdentifier("tradeRooms.broadcast.floatingMini")
            }
        }
        .allowsHitTesting(coordinator.showsFloatingMiniPlayer)
        .animation(.snappy(duration: 0.32), value: coordinator.miniPlayerCorner)
        .animation(.snappy(duration: 0.24), value: coordinator.showsFloatingMiniPlayer)
        .onAppear { tabBarMetrics.refresh() }
    }

    @ViewBuilder
    private func miniPlayer(layout: BroadcastMiniPlayerLayoutMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black
            LiveKitBroadcastVideoView(
                track: coordinator.videoTrackForMiniPlayer,
                onFirstFrame: { coordinator.markProgramVideoFrameRendered() }
            )
            .id(coordinator.programVideoTrackRevision)
            .opacity(coordinator.hasDisplayableProgramVideo ? 1 : 0)

            if let placeholder = coordinator.programVideoPlaceholder {
                BroadcastProgramVideoPlaceholderOverlay(presentation: placeholder, compact: true)
            }

            liveBadge
        }
        .frame(width: layout.playerSize.width, height: layout.playerSize.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture {
            ExperienceHaptics.play(.selection)
            coordinator.presentViewer()
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Live stream")
        .accessibilityHint("Opens full livestream")
    }

    private var liveBadge: some View {
        Text("LIVE")
            .font(.system(size: 8, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule(style: .continuous).fill(Color.red.opacity(0.92)))
            .padding(6)
    }

    private func dragGesture(layout: BroadcastMiniPlayerLayoutMetrics) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                isDragging = true
                dragTranslation = value.translation
            }
            .onEnded { value in
                isDragging = false
                let base = anchorCenter(for: coordinator.miniPlayerCorner, layout: layout)
                let proposed = CGPoint(
                    x: base.x + value.translation.width,
                    y: base.y + value.translation.height
                )
                let corner = BroadcastMiniPlayerLayout.nearestCorner(
                    to: proposed,
                    playerSize: layout.playerSize,
                    in: layout.draggableBounds
                )
                coordinator.setMiniPlayerCorner(corner)
                dragTranslation = .zero
            }
    }

    private func currentCenter(layout: BroadcastMiniPlayerLayoutMetrics) -> CGPoint {
        let anchor = anchorCenter(for: coordinator.miniPlayerCorner, layout: layout)
        if isDragging {
            return CGPoint(
                x: anchor.x + dragTranslation.width,
                y: anchor.y + dragTranslation.height
            )
        }
        return anchor
    }

    private func anchorCenter(
        for corner: BroadcastMiniPlayerCorner,
        layout: BroadcastMiniPlayerLayoutMetrics
    ) -> CGPoint {
        BroadcastMiniPlayerLayout.center(
            for: corner,
            playerSize: layout.playerSize,
            in: layout.draggableBounds
        )
    }

    private func layoutMetrics(in proxy: GeometryProxy) -> BroadcastMiniPlayerLayoutMetrics {
        BroadcastMiniPlayerLayout.makeLayout(
            containerSize: proxy.size,
            safeArea: proxy.safeAreaInsets,
            tabBarTopInsetFromBottom: tabBarMetrics.tabBarTopInsetFromBottom,
            horizontalMargin: horizontalMargin,
            verticalMargin: verticalMargin,
            maxPlayerWidth: maxPlayerWidth,
            widthToScreenRatio: widthToScreenRatio
        )
    }

}

struct BroadcastMiniPlayerLayoutMetrics: Equatable {
    var playerSize: CGSize
    var draggableBounds: CGRect
}

enum BroadcastMiniPlayerLayout {
    /// Extra space below the status bar / Dynamic Island for top-corner snap (pt).
    static let topCornerExtraPadding: CGFloat = 14

    static func makeLayout(
        containerSize: CGSize,
        safeArea: EdgeInsets,
        tabBarTopInsetFromBottom: CGFloat,
        horizontalMargin: CGFloat,
        verticalMargin: CGFloat,
        maxPlayerWidth: CGFloat,
        widthToScreenRatio: CGFloat
    ) -> BroadcastMiniPlayerLayoutMetrics {
        let usableWidth = max(120, min(maxPlayerWidth, containerSize.width * widthToScreenRatio))
        let playerSize = CGSize(width: usableWidth, height: usableWidth * 9 / 16)

        let topSafe = resolvedTopSafeArea(safeArea)
        let top = topSafe + Self.topCornerExtraPadding + playerSize.height / 2
        let bottom = max(
            top,
            containerSize.height - tabBarTopInsetFromBottom - verticalMargin - playerSize.height / 2
        )
        let leading = safeArea.leading + horizontalMargin + playerSize.width / 2
        let trailing = max(
            leading,
            containerSize.width - safeArea.trailing - horizontalMargin - playerSize.width / 2
        )

        let bounds = CGRect(
            x: leading,
            y: top,
            width: max(0, trailing - leading),
            height: max(0, bottom - top)
        )
        return BroadcastMiniPlayerLayoutMetrics(
            playerSize: playerSize,
            draggableBounds: bounds
        )
    }

    /// Overlay ignores safe area — `GeometryReader` often reports `top == 0`; use the key window then.
    static func resolvedTopSafeArea(_ safeArea: EdgeInsets) -> CGFloat {
        let windowTop = keyWindowSafeAreaInsets().top
        if safeArea.top > 0 {
            return max(safeArea.top, windowTop)
        }
        return windowTop
    }

    private static func keyWindowSafeAreaInsets() -> UIEdgeInsets {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        else { return .zero }
        return window.safeAreaInsets
    }

    static func center(
        for corner: BroadcastMiniPlayerCorner,
        playerSize: CGSize,
        in draggableBounds: CGRect
    ) -> CGPoint {
        switch corner {
        case .topLeading:
            return CGPoint(x: draggableBounds.minX, y: draggableBounds.minY)
        case .topTrailing:
            return CGPoint(x: draggableBounds.maxX, y: draggableBounds.minY)
        case .bottomLeading:
            return CGPoint(x: draggableBounds.minX, y: draggableBounds.maxY)
        case .bottomTrailing:
            return CGPoint(x: draggableBounds.maxX, y: draggableBounds.maxY)
        }
    }

    static func nearestCorner(
        to point: CGPoint,
        playerSize: CGSize,
        in draggableBounds: CGRect
    ) -> BroadcastMiniPlayerCorner {
        let clampedX = min(max(point.x, draggableBounds.minX), draggableBounds.maxX)
        let clampedY = min(max(point.y, draggableBounds.minY), draggableBounds.maxY)
        let clamped = CGPoint(x: clampedX, y: clampedY)

        let midX = (draggableBounds.minX + draggableBounds.maxX) / 2
        let midY = (draggableBounds.minY + draggableBounds.maxY) / 2
        let isLeading = clamped.x <= midX
        let isTop = clamped.y <= midY

        switch (isTop, isLeading) {
        case (true, true): return .topLeading
        case (true, false): return .topTrailing
        case (false, true): return .bottomLeading
        case (false, false): return .bottomTrailing
        }
    }
}

extension View {
    func broadcastFloatingMiniPlayerOverlay(coordinator: RoomBroadcastCoordinator) -> some View {
        overlay {
            BroadcastFloatingMiniPlayerOverlay(coordinator: coordinator)
                .ignoresSafeArea()
        }
    }
}