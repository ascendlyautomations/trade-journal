import SwiftUI

struct TradingRulesRuleDetailView: View {
    let ruleIDRaw: String
    let navigationCoordinator: NavigationCoordinator
    let detailCache: DetailPresentationCache

    @Bindable private var session: TradingRulesComplianceSessionStore
    @Environment(\.themeColors) private var colors
    @State private var showsTradesSheet = false

    init(ruleIDRaw: String, navigationCoordinator: NavigationCoordinator, detailCache: DetailPresentationCache) {
        self.ruleIDRaw = ruleIDRaw
        self.navigationCoordinator = navigationCoordinator
        self.detailCache = detailCache
        _session = Bindable(TradingRulesCompliancePresentationStores.store(detailCache: detailCache))
    }

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

    private var tradeOutcomes: TradingRulesRuleTradeOutcomePresentation.GroupedOutcomes {
        guard let ruleID, let checks = session.result?.complianceChecks else {
            return TradingRulesRuleTradeOutcomePresentation.GroupedOutcomes(followed: [], violated: [])
        }
        return TradingRulesRuleTradeOutcomePresentation.groupedTradeOutcomes(
            ruleID: ruleID,
            checks: checks
        )
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
                                    guard TradingRulesAnalyticsPreviewSupport.allowsTradeDetailNavigation(tradeID: tradeID)
                                    else { return }
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
        .safeAreaInset(edge: .top, spacing: 0) {
            if TradingRulesAnalyticsPreviewSupport.showsSampleDataChrome {
                TradingRulesAnalyticsSampleDataBanner(compactListSubtitle: true)
            }
        }
        .accessibilityIdentifier("tradingRulesAnalytics.ruleDetail")
        .sheet(isPresented: $showsTradesSheet) {
            if let snapshot {
                TradingRulesRuleTradesSheet(
                    ruleLabel: snapshot.ruleLabel,
                    outcomes: tradeOutcomes,
                    onOpenTrade: { tradeID in
                        guard TradingRulesAnalyticsPreviewSupport.allowsTradeDetailNavigation(tradeID: tradeID)
                        else { return }
                        navigationCoordinator.pushTradeDetail(tradeID, cache: detailCache)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func statsCard(_ snapshot: TradingRulesViolationPatterns.RuleDrillDownSnapshot) -> some View {
        let outcomes = tradeOutcomes
        let insufficient = snapshot.evaluated > 0 && snapshot.evaluated < 3 && outcomes.total == 0

        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            Text(snapshot.adherencePercent.map { String(format: "%.1f%% compliance", $0) } ?? "–")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(colors.primaryText)

            Text("Trade outcomes")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.primaryText)

            if insufficient {
                Text("Fewer than 3 evaluated checks in scope—adherence is hidden until more data is available.")
                    .experienceStyle(.caption, color: colors.tertiaryText)
            }

            TradingRulesRuleOutcomeBarChart(
                followedCount: outcomes.followedCount,
                violatedCount: outcomes.violatedCount
            )

            if outcomes.total > 0 {
                HStack {
                    Spacer(minLength: 0)
                    Button("View All Trades") {
                        showsTradesSheet = true
                    }
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(colors.accent)
                    .accessibilityIdentifier("tradingRulesAnalytics.ruleDetail.viewAllTrades")
                }
            }

            Text("\(snapshot.evaluated) evaluated checks in scope. Unevaluated checks lack reliable data; not-applicable checks are excluded from adherence.")
                .experienceStyle(.caption2, color: colors.tertiaryText)
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceTradingRulesCard(prominence: .standard)
    }

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        return formatter
    }()

    private static let dayDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    @ViewBuilder
    private func violationsList(_ violations: [TradingRulesComplianceAnalytics.ViolationEvent]) -> some View {
        let sections = TradingRulesViolationGrouping.violationsByDayKey(violations)

        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Violations")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.primaryText)
            if sections.isEmpty {
                Text("No violations for this rule in the current scope.")
                    .experienceStyle(.caption, color: colors.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                    ForEach(sections, id: \.dayKey) { section in
                        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                            Text(dayHeading(for: section.dayKey))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(colors.secondaryText)
                            VStack(spacing: 0) {
                                ForEach(Array(section.violations.enumerated()), id: \.element.id) { index, event in
                                    TradingRulesViolationEventRow(
                                        event: event,
                                        onOpenTrade: { tradeID in
                                            navigationCoordinator.pushTradeDetail(tradeID, cache: detailCache)
                                        }
                                    )
                                    if index < section.violations.count - 1 {
                                        ExperienceDivider()
                                            .padding(.leading, 36)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func dayHeading(for dayKey: String) -> String {
        if let date = Self.dayKeyFormatter.date(from: dayKey) {
            return Self.dayDisplayFormatter.string(from: date)
        }
        return dayKey
    }
}