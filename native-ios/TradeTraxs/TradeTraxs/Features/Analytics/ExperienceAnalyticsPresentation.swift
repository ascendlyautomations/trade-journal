import SwiftUI

/// Popover chrome for Trading Rules Analytics metric explainers.
struct ExperienceAnalyticsPopoverChrome: ViewModifier {
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        content
            .background(colors.elevatedSurface)
            .presentationBackground(colors.elevatedSurface)
            .presentationCompactAdaptation(.popover)
    }
}

/// Sheet chrome for Trading Rules Analytics lists (View all, violations, etc.).
struct ExperienceAnalyticsSheetChrome: ViewModifier {
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(colors.sheetBackground)
            .presentationBackground(colors.sheetBackground)
            .experienceSheetChrome()
    }
}

extension View {
    func experienceAnalyticsPopoverChrome() -> some View {
        modifier(ExperienceAnalyticsPopoverChrome())
    }

    func experienceAnalyticsSheetChrome() -> some View {
        modifier(ExperienceAnalyticsSheetChrome())
    }
}
