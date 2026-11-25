import SwiftUI

/// Free-tier Psychology Analytics: sample overview + explorable Check-In History only.
struct PsychologyAnalyticsFreePreviewView: View {
    let presentation: PsychologyAnalyticsPreviewSupport.SamplePresentation
    var onOpenCheckInHistory: () -> Void
    var onOpenDay: ((CheckInHistoryDaySummary) -> Void)?

    @Environment(\.themeColors) private var colors

    private var inlineHistoryRows: [CheckInHistoryDaySummary] {
        Array(
            presentation.historySummaries.prefix(PsychologyAnalyticsPreviewSupport.inlineHistoryPreviewCount)
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                sampleDataBanner
                PsychologyAnalyticsDetailView(
                    report: presentation.report,
                    unlockProgress: presentation.unlockProgress,
                    onOpenCheckInHistory: onOpenCheckInHistory,
                    onOpenCheckInHistoryDay: onOpenDay,
                    freePreviewHistorySummaries: inlineHistoryRows
                )
                PsychologyAnalyticsPremiumLockedSection()
                    .padding(.horizontal, ExperienceSpacing.md)
            }
            .padding(.vertical, ExperienceSpacing.md)
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Psychology Analytics")
        .accessibilityIdentifier("psychologyAnalytics.freePreview")
    }

    private var sampleDataBanner: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.accent)
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text("Sample data preview")
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(.semibold)
                Text(MonetizationPlanCopy.psychologyAnalyticsPreviewSampleDataNote)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(cornerRadius: ExperienceRadius.md)
        .padding(.horizontal, ExperienceSpacing.md)
        .accessibilityIdentifier("psychologyAnalytics.sampleDataBanner")
    }
}