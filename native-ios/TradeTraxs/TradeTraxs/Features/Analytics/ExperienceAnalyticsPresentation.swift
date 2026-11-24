import SwiftUI
import UIKit

/// Layout tokens for Dashboard Scorecard-style metric explainers (all ⓘ popovers).
enum ExperienceInfoPopoverMetrics {
    /// Reference width for iPhone (TradeTraxs Scorecard section on Dashboard).
    static let compactWidth: CGFloat = 320
    static let regularWidth: CGFloat = 360
    static let horizontalInsetFromScreen: CGFloat = 40
    static let bodyLineSpacing: CGFloat = 3

    static func resolvedWidth(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        let preferred = horizontalSizeClass == .regular ? regularWidth : compactWidth
        let screen = UIScreen.main.bounds.width
        return min(preferred, max(280, screen - horizontalInsetFromScreen))
    }
}

/// Popover body, matches Dashboard **TradeTraxs Scorecard** ⓘ (title + explanation).
struct ExperienceInfoPopoverContent: View {
    let title: String
    let bodyText: String

    @Environment(\.themeColors) private var colors
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var contentWidth: CGFloat {
        ExperienceInfoPopoverMetrics.resolvedWidth(horizontalSizeClass: horizontalSizeClass)
    }

    var body: some View {
        let displayTitle = GeneratedProseNormalizer.normalize(title)
        let displayBody = GeneratedProseNormalizer.normalize(bodyText)
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text(displayTitle)
                .font(ExperienceTypography.subheadline.weight(.semibold))
                .foregroundStyle(colors.primaryText)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(displayBody)
                .font(ExperienceTypography.footnote)
                .foregroundStyle(colors.secondaryText)
                .lineSpacing(ExperienceInfoPopoverMetrics.bodyLineSpacing)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ExperienceSpacing.md)
        .frame(width: contentWidth, alignment: .leading)
        .experienceAnalyticsPopoverChrome()
    }
}

/// Popover chrome for Trading Rules Analytics metric explainers.
struct ExperienceAnalyticsPopoverChrome: ViewModifier {
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        content
            .background(colors.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
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

/// Standard ⓘ popover trigger used app-wide (Dashboard Scorecard reference).
typealias ExperienceInfoPopoverButton = AnalyticsMetricInfoButton

extension View {
    func experienceAnalyticsPopoverChrome() -> some View {
        modifier(ExperienceAnalyticsPopoverChrome())
    }

    func experienceAnalyticsSheetChrome() -> some View {
        modifier(ExperienceAnalyticsSheetChrome())
    }
}