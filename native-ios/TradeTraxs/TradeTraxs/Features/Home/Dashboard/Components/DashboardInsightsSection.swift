import SwiftUI

struct DashboardInsightsSection: View {
    let insights: [DashboardInsightItem]
    /// When false, the parent owns the section title (Phase 1 hierarchy).
    var showsTitle: Bool = true

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            if showsTitle {
                Text("Insights")
                    .experienceStyle(.headline, color: colors.primaryText)
                    .padding(.horizontal, ExperienceSpacing.md)
            }

            if insights.isEmpty {
                Text("Log a few more trades and we’ll surface coaching recommendations here.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .padding(.horizontal, ExperienceSpacing.md)
            } else {
                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                        insightCard(insight)
                            .opacity(1)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, ExperienceSpacing.md)
                .animation(
                    ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                    value: insights.map(\.id)
                )
            }
        }
        .accessibilityIdentifier("dashboard.insights")
    }

    private func insightCard(_ insight: DashboardInsightItem) -> some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.md) {
            ExperienceIcon(
                icon: icon(for: insight.kind),
                size: .md,
                color: colors.accent
            )
            .frame(width: 40, height: 40)
            .background(colors.accent.opacity(0.14), in: Circle())
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                Text("Coach")
                    .experienceStyle(.caption2, color: colors.accent)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(insight.title)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(.semibold)
                Text(insight.body)
                    .experienceStyle(.callout, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(ExperienceSpacing.md)
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
        .accessibilityLabel("\(insight.title). \(insight.body)")
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
