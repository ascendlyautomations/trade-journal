import SwiftUI

struct TradingRulesDisciplineProgressSection: View {
    let progress: TradingRulesDisciplineProgress.Bundle
    var onOpenRule: ((TradingRulesComplianceAnalytics.RuleID) -> Void)?

    @Environment(\.themeColors) private var colors
    @State private var detailsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            AnalyticsSectionHeader(
                title: "Discipline progress",
                infoTitle: "Discipline progress",
                infoBody: """
                Compares current dashboard scope to the prior period of equal length. \
                Streaks count only evaluated Eastern trading days with enough checks; missing days are skipped. \
                Your compliance goal is informational and does not change rule scoring.
                """,
                infoAccessibilityID: "tradingRulesAnalytics.discipline.info"
            )

            if progress.insufficientData {
                Text("Not enough evaluated checks in this scope yet.")
                    .experienceStyle(.caption, color: colors.secondaryText)
            } else {
                summaryRow
                if detailsExpanded {
                    detailContent
                }
                Button(detailsExpanded ? "Hide details" : "Show details") {
                    detailsExpanded.toggle()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(colors.accent)
            }
        }
    }

    @ViewBuilder
    private var summaryRow: some View {
        HStack(spacing: ExperienceSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Goal \(Int(progress.goalPercent))%")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                Text("\(progress.daysMeetingGoal)/\(progress.evaluatedDaysInScope) days")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(colors.primaryText)
            }
            Spacer()
            if progress.periodCompareSufficient, let delta = progress.adherenceDeltaPoints {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("vs prior period")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                    Text(String(format: "%+.1f pts", delta))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(delta >= 0 ? colors.profit : colors.loss)
                }
            }
            if progress.goalStreakDays > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Goal streak")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                    Text("\(progress.goalStreakDays)d")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(colors.primaryText)
                }
            }
        }
        .padding(ExperienceSpacing.md)
        .experienceTradingRulesCard(prominence: .standard)
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            if !progress.historyPoints.isEmpty {
                TradingRulesComplianceTrendCharts(
                    weekly: progress.historyPoints.map {
                        TradingRulesComplianceAnalytics.TrendPoint(
                            key: $0.key,
                            label: $0.label,
                            adherencePercent: $0.adherencePercent,
                            evaluated: $0.evaluated,
                            followed: 0,
                            violations: 0,
                            unevaluatedChecks: 0,
                            tradeCount: 0,
                            insufficientData: $0.insufficientData,
                            coverageNote: nil
                        )
                    },
                    monthly: [],
                    layout: .compact
                )
            }

            if let improved = progress.mostImprovedRule {
                ruleDeltaRow(title: "Most improved", delta: improved, improved: true)
            }
            if let declined = progress.mostDeclinedRule {
                ruleDeltaRow(title: "Most declined", delta: declined, improved: false)
            }
        }
    }

    @ViewBuilder
    private func ruleDeltaRow(
        title: String,
        delta: TradingRulesDisciplineProgress.RuleDelta,
        improved: Bool
    ) -> some View {
        let tappable = onOpenRule != nil
        Button {
            onOpenRule?(delta.ruleID)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                    Text(delta.ruleLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                }
                Spacer()
                Text(String(format: "%+.1f pts violation rate", delta.deltaPoints))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(improved ? colors.profit : colors.loss)
                if tappable {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(colors.tertiaryText)
                }
            }
            .padding(ExperienceSpacing.sm)
            .experienceTradingRulesCard(prominence: .standard)
        }
        .buttonStyle(.plain)
        .disabled(!tappable)
    }
}
