import SwiftUI

enum DashboardScorecardDisplayCopy {
    static let sectionTitle = "TradeTraxs Scorecard"
}

/// Compact visual scorecard card for the Home dashboard (native-first; not web layout).
struct DashboardTradingScorecardSection: View {
    @Bindable private var session = TradingScorecardSessionStore.shared
    /// When false, the dashboard section header supplies the title.
    var showsTitle: Bool = true
    var onOpenDetail: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Group {
            if !session.ready {
                loadingPlaceholder
            } else if let result = session.result {
                card(result: result)
            } else {
                emptyCard
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .accessibilityIdentifier("dashboard.scorecard")
    }

    private func card(result: ScorecardResult) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            HStack(alignment: .center) {
                if showsTitle {
                    Text(DashboardScorecardDisplayCopy.sectionTitle)
                        .experienceStyle(.headline, color: colors.primaryText)
                }
                Spacer(minLength: ExperienceSpacing.sm)
                Button(action: onOpenDetail) {
                    HStack(spacing: 4) {
                        Text("View Breakdown")
                            .experienceStyle(.caption, color: colors.accent)
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(colors.accent)
                    }
                }
                .accessibilityLabel("View TradeTraxs Scorecard breakdown")
                .accessibilityIdentifier("dashboard.scorecard.viewDetail")
            }

            HStack(alignment: .center, spacing: ExperienceSpacing.lg) {
                ScorecardScoreRingView(
                    score: result.overall.status == .ready ? result.overall.score : nil,
                    buildingProgress: result.overall.score == nil
                        ? ScorecardVisualSupport.overallBuildingRingProgress(result: result)
                        : nil,
                    buildingHint: ScorecardVisualSupport.overallBuildingHint(result: result),
                    size: 88,
                    lineWidth: 9
                )

                VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                    Text("\(result.overall.tradeCount) trades · \(result.overall.tradingDayCount) days")
                        .experienceStyle(.caption, color: colors.secondaryText)
                    ForEach(result.adherence) { row in
                        HStack {
                            Text(row.label)
                                .experienceStyle(.caption, color: colors.secondaryText)
                            Spacer(minLength: 8)
                            Text(row.value ?? row.pending ?? "")
                                .experienceStyle(.caption, color: colors.primaryText)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let insight = result.insights.first {
                DashboardExpandableInsightText(
                    text: insight.text,
                    accessibilityIdentifier: "dashboard.scorecard.insight"
                )
            }
        }
        .padding(ExperienceSpacing.md)
        .experienceDashboardCard(prominence: .featured)
    }

    private var loadingPlaceholder: some View {
        ExperienceSkeleton(height: 120, cornerRadius: ExperienceRadius.lg)
            .accessibilityIdentifier("dashboard.scorecard.loading")
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text(DashboardScorecardDisplayCopy.sectionTitle)
                .experienceStyle(.headline, color: colors.primaryText)
            Text("Log trades in this scope to start.")
                .experienceStyle(.caption, color: colors.secondaryText)
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(prominence: .featured)
        .accessibilityIdentifier("dashboard.scorecard.empty")
    }
}
