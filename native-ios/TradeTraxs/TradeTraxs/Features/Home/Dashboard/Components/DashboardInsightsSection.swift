import SwiftUI

struct DashboardInsightsSection: View {
    let title: String
    var subtitle: String? = nil
    let insights: [DashboardInsightItem]

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSectionExpanded = true
    @State private var showsAllInsights = false

    private var visibleInsights: [DashboardInsightItem] {
        guard insights.count > DashboardInsightPresentation.previewCount, !showsAllInsights else {
            return insights
        }
        return Array(insights.prefix(DashboardInsightPresentation.previewCount))
    }

    private var showsViewMore: Bool {
        insights.count > DashboardInsightPresentation.previewCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            DashboardCollapsibleSectionHeader(
                title: title,
                subtitle: subtitle,
                isExpanded: isSectionExpanded,
                onToggle: { isSectionExpanded.toggle() }
            )

            if isSectionExpanded {
                if insights.isEmpty {
                    Text("Log a few more trades and we’ll surface coaching recommendations here.")
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .padding(.horizontal, ExperienceSpacing.md)
                        .padding(.bottom, ExperienceSpacing.xs)
                } else {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                        ForEach(visibleInsights) { insight in
                            insightCard(insight)
                        }
                        if showsViewMore {
                            DashboardInsightViewMoreControl(isExpanded: showsAllInsights) {
                                ExperienceHaptics.play(.selection)
                                withAnimation(
                                    ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion)
                                ) {
                                    showsAllInsights.toggle()
                                }
                            }
                            .padding(.horizontal, ExperienceSpacing.md)
                        }
                    }
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.bottom, ExperienceSpacing.xs)
                    .animation(
                        ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                        value: visibleInsights.map(\.id)
                    )
                }
            }
        }
        .accessibilityIdentifier("dashboard.insights")
    }

    private func insightCard(_ insight: DashboardInsightItem) -> some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            ExperienceIcon(
                icon: icon(for: insight.kind),
                size: .sm,
                color: colors.accent
            )
            .frame(width: 32, height: 32)
            .background(colors.accent.opacity(0.14), in: Circle())
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Coach")
                    .experienceStyle(.caption2, color: colors.accent)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .tracking(0.4)
                Text(insight.displayTitle)
                    .experienceStyle(.footnote, color: colors.primaryText)
                    .fontWeight(.semibold)
                Text(insight.displayBody)
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(
            cornerRadius: ExperienceRadius.md,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .stroke(colors.accent.opacity(0.18), lineWidth: ExperienceBorder.hairline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(insight.displayTitle). \(insight.displayBody)")
        .accessibilityIdentifier("dashboard.insight.\(insight.id)")
    }

    private func icon(for kind: DashboardInsightKind) -> AppIcon {
        switch kind {
        case .session: return .calendar
        case .symbol: return .chart
        case .direction: return .trades
        }
    }
}
