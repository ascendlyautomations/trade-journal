import SwiftUI

struct TradingRulesRuleDetailView: View {
    let ruleIDRaw: String
    let navigationCoordinator: NavigationCoordinator
    let detailCache: DetailPresentationCache

    @Bindable private var session = TradingRulesComplianceSessionStore.shared
    @Environment(\.themeColors) private var colors

    private var ruleID: TradingRulesComplianceAnalytics.RuleID? {
        TradingRulesComplianceAnalytics.RuleID(rawValue: ruleIDRaw)
    }

    private var snapshot: TradingRulesViolationPatterns.RuleDrillDownSnapshot? {
        guard let ruleID, let result = session.result else { return nil }
        return result.violationPatterns.ruleDrillDown[ruleID]
    }

    private var impactRow: TradingRulesComplianceAnalytics.ImpactRow? {
        guard let ruleID, let result = session.result else { return nil }
        return result.impacts.first { $0.ruleID == ruleID }
    }

    var body: some View {
        Group {
            if let snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                        if !session.scopeLabel.isEmpty {
                            Text(session.scopeLabel)
                                .experienceStyle(.caption, color: colors.secondaryText)
                        }

                        statsCard(snapshot)

                        if let impactRow {
                            TradingRulesRuleImpactDetailSection(
                                row: impactRow,
                                onOpenTrade: { tradeID in
                                    navigationCoordinator.pushTradeDetail(tradeID, cache: detailCache)
                                }
                            )
                        }

                        if !snapshot.weeklyTrend.isEmpty {
                            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                                Text("Weekly trend")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(colors.primaryText)
                                TradingRulesComplianceTrendCharts(
                                    weekly: snapshot.weeklyTrend,
                                    monthly: [],
                                    layout: .compact
                                )
                            }
                        }

                        violationsList(snapshot.violations)
                    }
                    .padding(ExperienceSpacing.md)
                }
            } else {
                ExperienceEmptyState(
                    icon: .chart,
                    title: "No data for this rule",
                    message: "Return to Trading Rules Analytics or widen your dashboard filters."
                )
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle(snapshot?.ruleLabel ?? "Rule detail")
        .accessibilityIdentifier("tradingRulesAnalytics.ruleDetail")
    }

    @ViewBuilder
    private func statsCard(_ snapshot: TradingRulesViolationPatterns.RuleDrillDownSnapshot) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            Text(snapshot.adherencePercent.map { String(format: "%.1f%% compliance", $0) } ?? "—")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(colors.primaryText)

            HStack(spacing: ExperienceSpacing.xs) {
                miniStat(title: "Followed", value: snapshot.followed, tone: colors.profit)
                miniStat(title: "Violations", value: snapshot.violated, tone: colors.loss)
                miniStat(title: "Unevaluated", value: snapshot.unevaluated, tone: colors.secondaryText)
            }

            Text("\(snapshot.evaluated) evaluated checks in scope. Unevaluated checks lack reliable data; not-applicable checks are excluded from adherence.")
                .experienceStyle(.caption2, color: colors.tertiaryText)
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceTradingRulesCard(prominence: .standard)
    }

    @ViewBuilder
    private func miniStat(title: String, value: Int, tone: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .experienceStyle(.caption2, color: colors.tertiaryText)
            Text("\(value)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(tone)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ExperienceSpacing.sm)
        .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
    }

    @ViewBuilder
    private func violationsList(_ violations: [TradingRulesComplianceAnalytics.ViolationEvent]) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Violations")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.primaryText)
            if violations.isEmpty {
                Text("No violations for this rule in the current scope.")
                    .experienceStyle(.caption, color: colors.secondaryText)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(violations.enumerated()), id: \.element.id) { index, event in
                        TradingRulesViolationEventRow(
                            event: event,
                            onOpenTrade: { tradeID in
                                navigationCoordinator.pushTradeDetail(tradeID, cache: detailCache)
                            }
                        )
                        if index < violations.count - 1 {
                            ExperienceDivider()
                                .padding(.leading, 36)
                        }
                    }
                }
            }
        }
    }
}
