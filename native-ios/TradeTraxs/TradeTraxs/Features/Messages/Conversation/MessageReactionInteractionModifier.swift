import SwiftUI

/// Long-press reaction picker + double-tap primary like for message bubbles.
struct MessageReactionInteractionModifier: ViewModifier {
    let isEnabled: Bool
    let onLongPress: () -> Void
    let onDoubleTapLike: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.38, maximumDistance: 12) {
                    ExperienceHaptics.play(.impactLight)
                    onLongPress()
                }
                .experienceDoubleTapLike(isEnabled: true, perform: onDoubleTapLike)
        } else {
            content
        }
    }
}

extension View {
    func messageReactionInteractions(
        isEnabled: Bool,
        onLongPress: @escaping () -> Void,
        onDoubleTapLike: @escaping () -> Void
    ) -> some View {
        modifier(
            MessageReactionInteractionModifier(
                isEnabled: isEnabled,
                onLongPress: onLongPress,
                onDoubleTapLike: onDoubleTapLike
            )
        )
    }
}
