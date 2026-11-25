import SwiftUI

/// Shared vertical rhythm for Performance and Psychology report detail screens.
enum ReportDetailLayout {
    /// Space between major sections on a report detail scroll.
    static let sectionSpacing = ExperienceSpacing.md
    /// Space from the top header card to the first section (~half of ``sectionSpacing``).
    static let headerToFirstSectionSpacing = ExperienceSpacing.xs
}

/// Performance report detail navigation: no center title; period label trailing (This Week pattern).
struct ReportDetailPerformancePeriodLabel: View {
    let text: String

    @Environment(\.themeColors) private var colors

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colors.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("reports.detail.periodLabel")
    }
}

struct ReportDetailPerformanceNavigationChrome: ViewModifier {
    let periodLabel: String?
    let fallbackTitle: String

    func body(content: Content) -> some View {
        if let periodLabel {
            content
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ReportDetailPerformancePeriodLabel(text: periodLabel)
                    }
                }
        } else {
            content.experienceNavigationTitle(fallbackTitle)
        }
    }
}