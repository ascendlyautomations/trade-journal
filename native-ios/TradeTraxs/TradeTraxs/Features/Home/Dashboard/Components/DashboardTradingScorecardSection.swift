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

                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    if let consistency = result.categories.first(where: { $0.id == .consistency }) {
                        ScorecardCategoryBarRow(
                            title: "Consistency",
                            valueLabel: ScorecardVisualSupport.homeCategoryValueLabel(consistency),
                            fillFraction: ScorecardVisualSupport.categoryBarFillFraction(consistency),
                            tint: ScorecardVisualSupport.categoryBarRepresentsScore(consistency)
                                ? colors.accent
                                : colors.accentMuted,
                            representsScore: ScorecardVisualSupport.categoryBarRepresentsScore(consistency)
                        )
                    }
                    if let discipline = result.categories.first(where: { $0.id == .discipline }) {
                        ScorecardCategoryBarRow(
                            title: "Discipline",
                            valueLabel: ScorecardVisualSupport.homeCategoryValueLabel(discipline),
                            fillFraction: ScorecardVisualSupport.categoryBarFillFraction(discipline),
                            tint: ScorecardVisualSupport.categoryBarRepresentsScore(discipline)
                                ? colors.accent
                                : colors.accentMuted,
                            representsScore: ScorecardVisualSupport.categoryBarRepresentsScore(discipline)
                        )
                    }
                    HStack(spacing: ExperienceSpacing.md) {
                        if let risk = result.categories.first(where: { $0.id == .risk }) {
                            ScorecardPhase1Indicator(
                                kind: .risk,
                                coveragePercent: risk.coveragePercent,
                                caption: "\(risk.coveragePercent)% cov"
                            )
                        }
                        if let psych = result.categories.first(where: { $0.id == .psychology }) {
                            ScorecardPhase1Indicator(
                                kind: .psychology,
                                coveragePercent: psych.coveragePercent,
                                caption: matchedDaysCaption(psych)
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if result.overall.score == nil {
                ScorecardHomeCategorySnapshotGrid(result: result)
                ScorecardGateChipsRow(chips: ScorecardVisualSupport.overallBuildingGateChips(result: result))
            }

            if let footnote = ScorecardVisualSupport.overallBuildingFootnote(result: result) {
                Text(footnote)
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("\(result.overall.tradeCount) trades · \(result.overall.tradingDayCount) days")
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(ExperienceSpacing.md)
        .experienceDashboardCard(prominence: .featured)
    }

    private func matchedDaysCaption(_ psych: ScorecardCategoryResult) -> String {
        if let matched = psych.subMetrics.first(where: { $0.id == "psych.matched_days" }) {
            return matched.value + "d"
        }
        return "\(psych.coveragePercent)% cov"
    }

    private var loadingPlaceholder: some View {
        ExperienceSkeleton(height: 140, cornerRadius: ExperienceRadius.lg)
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
