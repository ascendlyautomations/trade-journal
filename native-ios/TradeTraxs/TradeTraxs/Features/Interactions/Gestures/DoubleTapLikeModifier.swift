import SwiftUI

/// Double-tap → callback + heart feedback. Business Like logic stays in the feature/store.
struct DoubleTapLikeModifier: ViewModifier {
    var isEnabled: Bool = true
    /// Optional single-tap (e.g. open detail). Fired only when the gesture is not a double-tap.
    var onSingleTap: (() -> Void)? = nil
    var onDoubleTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showHeart = false

    func body(content: Content) -> some View {
        content
            .overlay {
                LikeFeedbackOverlay(isVisible: showHeart, reduceMotion: reduceMotion)
            }
            .modifier(
                MediaTapGestureModifier(
                    isEnabled: isEnabled,
                    onSingleTap: onSingleTap,
                    onDoubleTap: {
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
        }
    }
}

/// Separates single vs double tap so detail open does not race Like.
private struct MediaTapGestureModifier: ViewModifier {
    var isEnabled: Bool
    var onSingleTap: (() -> Void)?
    var onDoubleTap: () -> Void

    func body(content: Content) -> some View {
        Group {
            if !isEnabled {
                content
            } else if let onSingleTap {
                content
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: onDoubleTap)
                    .onTapGesture(count: 1, perform: onSingleTap)
            } else {
                content
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: onDoubleTap)
            }
        }
    }
}

extension View {
    /// Double-tap Like with heart feedback. Optional single-tap for navigation.
    func experienceDoubleTapLike(
        isEnabled: Bool = true,
        onSingleTap: (() -> Void)? = nil,
        perform: @escaping () -> Void
    ) -> some View {
        modifier(
            DoubleTapLikeModifier(
                isEnabled: isEnabled,
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
        onSingleTap: (() -> Void)? = nil
    ) -> some View {
        experienceDoubleTapLike(isEnabled: isEnabled, onSingleTap: onSingleTap) {
            Task { await store.ensureLiked(on: target) }
        }
    }
}
