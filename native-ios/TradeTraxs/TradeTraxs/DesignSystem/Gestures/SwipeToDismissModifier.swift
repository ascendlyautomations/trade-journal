import SwiftUI
import UIKit

/// Drag-down interactive dismiss for immersive / modal surfaces.
///
/// Do **not** apply to normal NavigationStack pushes — those keep the system
/// leading-edge Back gesture.
struct SwipeToDismissModifier: ViewModifier {
    var isEnabled: Bool = true
    /// Minimum downward translation to dismiss.
    var distanceThreshold: CGFloat = 110
    /// Minimum downward velocity (pt/s) to dismiss.
    var velocityThreshold: CGFloat = 900
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(y: max(0, dragOffset))
            .opacity(dismissProgressOpacity)
            .simultaneousGesture(dismissGesture)
            .animation(
                ExperienceMotion.preferred(MotionSpring.snappy.animation, reduceMotion: reduceMotion),
                value: dragOffset
            )
    }

    private var dismissProgressOpacity: Double {
        guard dragOffset > 0 else { return 1 }
        let progress = min(1, dragOffset / 320)
        return 1 - (progress * 0.28)
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .onChanged { value in
                guard isEnabled else { return }
                // Prefer downward intent — ignore mostly-horizontal drags (paging / scrub).
                let horizontal = abs(value.translation.width)
                let vertical = value.translation.height
                guard vertical > 0, vertical > horizontal * 1.15 else {
                    if dragOffset != 0 { dragOffset = 0 }
                    return
                }
                dragOffset = vertical
            }
            .onEnded { value in
                guard isEnabled else {
                    dragOffset = 0
                    return
                }
                let vertical = value.translation.height
                let horizontal = abs(value.translation.width)
                let velocityY = value.predictedEndTranslation.height - value.translation.height
                let shouldDismiss =
                    vertical > 0
                    && vertical > horizontal * 1.05
                    && (vertical >= distanceThreshold || velocityY >= velocityThreshold)

                if shouldDismiss {
                    if reduceMotion {
                        dragOffset = 0
                        onDismiss()
                    } else {
                        ExperienceMotion.withAnimation(
                            MotionCurve.easeIn.animation(duration: .fast),
                            reduceMotion: false
                        ) {
                            dragOffset = UIScreen.main.bounds.height
                        }
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 120_000_000)
                            onDismiss()
                            dragOffset = 0
                        }
                    }
                } else {
                    ExperienceMotion.withAnimation(
                        MotionSpring.snappy.animation,
                        reduceMotion: reduceMotion
                    ) {
                        dragOffset = 0
                    }
                }
            }
    }
}

extension View {
    /// Swipe-down to dismiss immersive/modal content. Disabled when `isEnabled` is false
    /// (e.g. while an image is zoomed).
    func experienceSwipeToDismiss(
        isEnabled: Bool = true,
        distanceThreshold: CGFloat = 110,
        velocityThreshold: CGFloat = 900,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(
            SwipeToDismissModifier(
                isEnabled: isEnabled,
                distanceThreshold: distanceThreshold,
                velocityThreshold: velocityThreshold,
                onDismiss: onDismiss
            )
        )
    }
}
