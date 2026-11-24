import SwiftUI

/// Opaque modal presentation fill, replaces system sheet material (warm brown in dark mode).
struct ExperienceThemedPresentationBackground: ViewModifier {
    enum Surface {
        case sheet
        case fullScreen
    }

    var surface: Surface = .sheet
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        let fill = surface == .sheet ? colors.sheetBackground : colors.backgroundPrimary
        content
            .presentationBackground(fill)
            .background(fill)
    }
}

/// Shared sheet chrome, Apple-style detents, drag indicator, and corner radius.
///
/// Presentation-only. Does not change navigation destinations or business logic.
struct ExperienceSheetChrome: ViewModifier {
    var detents: Set<PresentationDetent> = [.medium, .large]
    var dragIndicator: Visibility = .visible
    var interactiveDismiss: Bool = true
    /// When false, omits the shared keyboard **Done** accessory (e.g. chat sheets that use Return = Send).
    var keyboardDoneToolbar: Bool = true

    func body(content: Content) -> some View {
        content
            .modifier(ExperienceThemedPresentationBackground(surface: .sheet))
            .presentationDetents(detents)
            .presentationDragIndicator(dragIndicator)
            .presentationCornerRadius(ExperienceRadius.sheet)
            .interactiveDismissDisabled(!interactiveDismiss)
            .experienceKeyboardDismissOnTapOutside()
            .modifier(ConditionalKeyboardDoneToolbar(enabled: keyboardDoneToolbar))
    }
}

private struct ConditionalKeyboardDoneToolbar: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.experienceKeyboardDoneToolbar()
        } else {
            content
        }
    }
}

extension View {
    /// Semantic fill behind sheets and full-screen covers (call on modal roots when not using ``experienceSheetChrome()``).
    func experienceThemedPresentationBackground(fullScreen: Bool = false) -> some View {
        modifier(
            ExperienceThemedPresentationBackground(surface: fullScreen ? .fullScreen : .sheet)
        )
    }

    /// Standard modal sheet chrome used across Create, Filters, New Chat, pickers.
    func experienceSheetChrome(
        detents: Set<PresentationDetent> = [.medium, .large],
        dragIndicator: Visibility = .visible,
        interactiveDismiss: Bool = true,
        keyboardDoneToolbar: Bool = true
    ) -> some View {
        modifier(
            ExperienceSheetChrome(
                detents: detents,
                dragIndicator: dragIndicator,
                interactiveDismiss: interactiveDismiss,
                keyboardDoneToolbar: keyboardDoneToolbar
            )
        )
    }

    /// Blocks swipe-down interactive dismissal on compose/edit forms with user-entered data.
    ///
    /// Pair with an explicit Close / Cancel toolbar action. Does **not** add custom swipe-to-dismiss
    /// and does not affect navigation back gestures inside a pushed stack.
    func experienceProtectedFormDismiss(_ disabled: Bool = true) -> some View {
        interactiveDismissDisabled(disabled)
    }

    /// Soft content reveal for detail screens, respects Reduce Motion.
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
