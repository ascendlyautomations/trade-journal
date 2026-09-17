import SwiftUI

/// Double-tap primary like for message bubbles (long-press uses unified context menu).
struct MessageReactionInteractionModifier: ViewModifier {
    let isEnabled: Bool
    let onDoubleTapLike: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .contentShape(Rectangle())
                .experienceDoubleTapLike(isEnabled: true, perform: onDoubleTapLike)
        } else {
            content
        }
    }
}

extension View {
    func messageReactionInteractions(
        isEnabled: Bool,
        onDoubleTapLike: @escaping () -> Void
    ) -> some View {
        modifier(
            MessageReactionInteractionModifier(
                isEnabled: isEnabled,
                onDoubleTapLike: onDoubleTapLike
            )
        )
    }
}
