import SwiftUI

struct TradingRulesPersonalInsightsSection: View {
    let insights: [DashboardInsightItem]

    @Environment(\.themeColors) private var colors
    @State private var showsAll = false

    private static let previewCount = 3

    private static let infoTitle = "Personal insights"
    private static let infoBody =
        "These come from the same dashboard engine as Personal Insights: your saved trading rules, loss-streak behavior, and discipline patterns for the current account filter and trade sample."

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack {
                AnalyticsSectionHeader(
                    title: "Personal insights",
                    infoTitle: Self.infoTitle,
                    infoBody: Self.infoBody,
                    infoAccessibilityID: "tradingRulesAnalytics.personalInsights.info"
                )
                Spacer(minLength: 0)
                if insights.count > Self.previewCount {
                    Button("View all") {
                        showsAll = true
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.accent)
                }
            }

            if insights.isEmpty {
                Text("No rule-related insights for this scope yet.")
                    .experienceStyle(.caption, color: colors.secondaryText)
            } else {
                VStack(spacing: ExperienceSpacing.xs) {
                    ForEach(Array(insights.prefix(Self.previewCount))) { item in
                        insightRow(item)
                    }
                }
            }
        }
        .sheet(isPresented: $showsAll) {
            TradingRulesPersonalInsightsSheet(insights: insights)
        }
    }

    @ViewBuilder
    private func insightRow(_ item: DashboardInsightItem) -> some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            Image(systemName: toneIcon(item.tone))
                .font(.caption)
                .foregroundStyle(toneColor(item.tone))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                if let rule = TradingRulesPersonalInsights.relatedRuleLabel(for: item) {
                    Text(rule)
                        .experienceStyle(.caption2, color: colors.accent)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                Text(item.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                    .lineLimit(1)
                Text(item.displayBody)
                    .experienceStyle(.caption2, color: colors.secondaryText)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(ExperienceSpacing.sm)
        .background(colors.fillSecondary.opacity(0.25), in: RoundedRectangle(cornerRadius: ExperienceRadius.md))
    }

    private func toneColor(_ tone: DashboardInsightTone) -> Color {
        switch tone {
        case .positive: return colors.profit
        case .negative: return colors.loss
        case .warning: return colors.warning
        case .neutral: return colors.accent
        }
    }

    private func toneIcon(_ tone: DashboardInsightTone) -> String {
        switch tone {
        case .positive: return "checkmark.circle.fill"
        case .negative: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .neutral: return "lightbulb.fill"
        }
    }
}

private struct TradingRulesPersonalInsightsSheet: View {
    let insights: [DashboardInsightItem]

    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(insights) { item in
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                        if let rule = TradingRulesPersonalInsights.relatedRuleLabel(for: item) {
                            Text(rule)
                                .experienceStyle(.caption2, color: colors.accent)
                                .fontWeight(.semibold)
                        }
                        Text(item.displayTitle)
                            .font(.subheadline.weight(.semibold))
                        Text(item.displayBody)
                            .experienceStyle(.caption, color: colors.secondaryText)
                    }
                    .padding(.vertical, ExperienceSpacing.xxs)
                    .listRowBackground(colors.elevatedSurface)
                }
            }
            .experiencePlainListStyle()
            .experienceNavigationTitle("Personal insights")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .experienceAnalyticsSheetChrome()
    }
}
