import SwiftUI

struct DashboardInsightsSection: View {
    let presentation: DashboardInsightsPresentation

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSectionExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            DashboardCollapsibleSectionHeader(
                title: "Insights",
                subtitle: "What your trading data is telling you",
                isExpanded: isSectionExpanded,
                onToggle: { isSectionExpanded.toggle() }
            )

            if isSectionExpanded {
                Group {
                    if presentation.isLoading {
                        loadingState
                    } else if presentation.isEmpty {
                        emptyState
                    } else {
                        content
                    }
                }
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.bottom, ExperienceSpacing.xs)
            }
        }
        .accessibilityIdentifier("dashboard.insights")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
            if !presentation.performance.isEmpty {
                insightGroup(title: "Performance", subtitle: "Session, symbol, and direction highlights") {
                    ForEach(presentation.performance) { insight in
                        insightCard(insight)
                    }
                }
            }
            if !presentation.advancedEdge.isEmpty {
                insightGroup(title: "Advanced Edge", subtitle: "Strongest combined setups (min. 3 trades)") {
                    ForEach(presentation.advancedEdge) { insight in
                        insightCard(insight)
                    }
                }
            }
            if !presentation.riskBehavior.isEmpty {
                insightGroup(title: "Risk & Behavior", subtitle: "Setups to review and behavioral flags") {
                    ForEach(presentation.riskBehavior) { insight in
                        insightCard(insight)
                    }
                }
            }
        }
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
            value: presentation
        )
    }

    private func insightGroup<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            }
            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                content()
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            ProgressView()
            Text("Loading insights…")
                .experienceStyle(.footnote, color: colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, ExperienceSpacing.sm)
        .accessibilityIdentifier("dashboard.insights.loading")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text("Not enough sample size yet")
                .experienceStyle(.footnote, color: colors.primaryText)
                .fontWeight(.semibold)
            Text("Need at least 3 trades in a session, symbol, or direction bucket for the current filters.")
                .experienceStyle(.caption, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, ExperienceSpacing.sm)
        .accessibilityIdentifier("dashboard.insights.empty")
    }

    private func insightCard(_ insight: DashboardInsightItem) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                ExperienceIcon(
                    icon: icon(for: insight.kind),
                    size: .sm,
                    color: toneColor(insight.tone)
                )
                .frame(width: 32, height: 32)
                .background(toneColor(insight.tone).opacity(0.14), in: Circle())
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.displayTitle)
                        .experienceStyle(.footnote, color: colors.primaryText)
                        .fontWeight(.semibold)
                    Text(insight.displayBody)
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let metric = insight.metric {
                Text(metric)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(toneColor(insight.tone))
                    .padding(.leading, 32 + ExperienceSpacing.sm)
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
                .stroke(toneColor(insight.tone).opacity(0.28), lineWidth: ExperienceBorder.hairline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(insight.displayTitle). \(insight.displayBody)")
        .accessibilityIdentifier("dashboard.insight.\(insight.id)")
    }

    private func toneColor(_ tone: DashboardInsightTone) -> Color {
        switch tone {
        case .positive: return colors.profit
        case .negative: return colors.loss
        case .warning: return colors.warning
        case .neutral: return colors.accent
        }
    }

    private func icon(for kind: DashboardInsightKind) -> AppIcon {
        switch kind {
        case .session: return .calendar
        case .symbol: return .chart
        case .direction: return .trades
        }
    }
}
