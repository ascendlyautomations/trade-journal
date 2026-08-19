import SwiftUI

/// Shared sheet chrome — Apple-style detents, drag indicator, and corner radius.
///
/// Presentation-only. Does not change navigation destinations or business logic.
struct ExperienceSheetChrome: ViewModifier {
    var detents: Set<PresentationDetent> = [.medium, .large]
    var dragIndicator: Visibility = .visible
    var interactiveDismiss: Bool = true

    func body(content: Content) -> some View {
        content
            .presentationDetents(detents)
            .presentationDragIndicator(dragIndicator)
            .presentationCornerRadius(ExperienceRadius.sheet)
            .interactiveDismissDisabled(!interactiveDismiss)
    }
}

extension View {
    /// Standard modal sheet chrome used across Create, Filters, New Chat, pickers.
    func experienceSheetChrome(
        detents: Set<PresentationDetent> = [.medium, .large],
        dragIndicator: Visibility = .visible,
        interactiveDismiss: Bool = true
    ) -> some View {
        modifier(
            ExperienceSheetChrome(
                detents: detents,
                dragIndicator: dragIndicator,
                interactiveDismiss: interactiveDismiss
            )
        )
    }

    /// Soft content reveal for detail screens — respects Reduce Motion.
    func experienceDetailEntry(
        revealed: Bool,
        reduceMotion: Bool
    ) -> some View {
        opacity(revealed || reduceMotion ? 1 : 0.001)
            .animation(
                ExperienceMotion.preferred(ExperienceMotion.navigation, reduceMotion: reduceMotion),
                value: revealed
            )
    }
}
