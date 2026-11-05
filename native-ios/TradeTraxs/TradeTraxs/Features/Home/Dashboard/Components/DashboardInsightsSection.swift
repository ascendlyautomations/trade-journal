import SwiftUI

struct DashboardInsightsSection: View {
    let presentation: DashboardInsightsPresentation

    @Environment(\.themeColors) private var colors
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
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            if !presentation.performance.isEmpty {
                insightGroup(title: "Performance") {
                    ForEach(presentation.performance) { insight in
                        insightCard(insight)
                    }
                }
            }
            if !presentation.advancedEdge.isEmpty {
                insightGroup(title: "Advanced Edge") {
                    ForEach(presentation.advancedEdge) { insight in
                        insightCard(insight)
                    }
                }
            }
            if !presentation.riskBehavior.isEmpty {
                insightGroup(title: "Risk & Behavior") {
                    ForEach(presentation.riskBehavior) { insight in
                        insightCard(insight)
                    }
                }
            }
        }
    }

    private func insightGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text(title)
                .experienceStyle(.subheadline, color: colors.primaryText)
                .fontWeight(.semibold)
                .accessibilityAddTraits(.isHeader)
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
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                if let metric = insight.metric {
                    Text(metric)
                        .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(toneColor(insight.tone))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }

                Text(insight.displayTitle)
                    .experienceStyle(.footnote, color: colors.primaryText)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                Text(insight.displayBody)
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            toneIndicator(for: insight)
        }
        .padding(ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(prominence: .standard)
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .stroke(toneColor(insight.tone).opacity(0.28), lineWidth: ExperienceBorder.hairline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: insight))
        .accessibilityIdentifier("dashboard.insight.\(insight.id)")
    }

    private func toneIndicator(for insight: DashboardInsightItem) -> some View {
        ExperienceIcon(
            icon: icon(for: insight.kind),
            size: .sm,
            color: toneColor(insight.tone)
        )
        .frame(width: 28, height: 28)
        .background(toneColor(insight.tone).opacity(0.14), in: Circle())
        .accessibilityHidden(true)
    }

    private func accessibilityLabel(for insight: DashboardInsightItem) -> String {
        if let metric = insight.metric {
            return "\(metric). \(insight.displayTitle). \(insight.displayBody)"
        }
        return "\(insight.displayTitle). \(insight.displayBody)"
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
