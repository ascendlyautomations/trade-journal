import SwiftUI

/// Double-tap → callback + heart feedback. Business Like logic stays in the feature/store.
struct DoubleTapLikeModifier: ViewModifier {
    var isEnabled: Bool = true
    /// When true, the heart burst appears at the double-tap location (Reels-style).
    var anchorsHeartToTapLocation: Bool = false
    /// Optional single-tap (e.g. open detail). Fired only when the gesture is not a double-tap.
    var onSingleTap: (() -> Void)? = nil
    var onDoubleTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showHeart = false
    @State private var heartCenter: CGPoint?

    func body(content: Content) -> some View {
        content
            .overlay {
                LikeFeedbackOverlay(
                    isVisible: showHeart,
                    reduceMotion: reduceMotion,
                    center: anchorsHeartToTapLocation ? heartCenter : nil
                )
            }
            .modifier(
                MediaTapGestureModifier(
                    isEnabled: isEnabled,
                    capturesTapLocation: anchorsHeartToTapLocation,
                    onSingleTap: onSingleTap,
                    onDoubleTap: { location in
                        if let location {
                            heartCenter = location
                        }
                        presentFeedback()
                        onDoubleTap()
                    }
                )
            )
    }

    private func presentFeedback() {
        ExperienceHaptics.play(.impactLight)
        if reduceMotion {
            showHeart = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 280_000_000)
                showHeart = false
                heartCenter = nil
            }
            return
        }
        ExperienceMotion.withAnimation(MotionSpring.bouncy.animation, reduceMotion: false) {
            showHeart = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 520_000_000)
            ExperienceMotion.withAnimation(
                MotionCurve.easeOut.animation(duration: .fast),
                reduceMotion: false
            ) {
                showHeart = false
            }
            heartCenter = nil
        }
    }
}

/// Separates single vs double tap so detail open does not race Like.
private struct MediaTapGestureModifier: ViewModifier {
    var isEnabled: Bool
    var capturesTapLocation: Bool
    var onSingleTap: (() -> Void)?
    var onDoubleTap: (CGPoint?) -> Void

    func body(content: Content) -> some View {
        Group {
            if !isEnabled {
                content
            } else if capturesTapLocation, let onSingleTap {
                content
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture(count: 2)
                            .onEnded { value in
                                onDoubleTap(value.location)
                            }
                    )
                    .onTapGesture(count: 1, perform: onSingleTap)
            } else if capturesTapLocation {
                content
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture(count: 2)
                            .onEnded { value in
                                onDoubleTap(value.location)
                            }
                    )
            } else if let onSingleTap {
                content
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        onDoubleTap(nil)
                    }
                    .onTapGesture(count: 1, perform: onSingleTap)
            } else {
                content
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        onDoubleTap(nil)
                    }
            }
        }
    }
}

extension View {
    /// Double-tap Like with heart feedback. Optional single-tap for navigation.
    func experienceDoubleTapLike(
        isEnabled: Bool = true,
        anchorsHeartToTapLocation: Bool = false,
        onSingleTap: (() -> Void)? = nil,
        perform: @escaping () -> Void
    ) -> some View {
        modifier(
            DoubleTapLikeModifier(
                isEnabled: isEnabled,
                anchorsHeartToTapLocation: anchorsHeartToTapLocation,
                onSingleTap: onSingleTap,
                onDoubleTap: perform
            )
        )
    }

    /// Convenience — calls ``EngagementStore/ensureLiked(on:)`` (like-only, not toggle).
    func experienceDoubleTapLike(
        target: InteractionTarget,
        store: EngagementStore,
        isEnabled: Bool = true,
        anchorsHeartToTapLocation: Bool = false,
        onSingleTap: (() -> Void)? = nil
    ) -> some View {
        experienceDoubleTapLike(
            isEnabled: isEnabled,
            anchorsHeartToTapLocation: anchorsHeartToTapLocation,
            onSingleTap: onSingleTap
        ) {
            Task { await store.ensureLiked(on: target) }
        }
    }
}
