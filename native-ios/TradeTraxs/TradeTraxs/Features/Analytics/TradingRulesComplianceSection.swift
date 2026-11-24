import SwiftUI

private enum TradingRulesViolationFormat {
    static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

struct TradingRulesComplianceSection: View {
    enum Presentation {
        /// Legacy collapsible blocks (settings previews).
        case compactCollapsible
        /// Free tier, adherence summary for the current scope.
        case freeOverview
        /// Dedicated analytics page, score, timeline, trends, and impact always visible.
        case expandedAnalyticsPage
    }

    let analytics: TradingRulesComplianceAnalytics.Result?
    var presentation: Presentation = .compactCollapsible
    var zeroEvalHint: String? = nil
    var personalInsights: [DashboardInsightItem] = []
    var activeDateRange: DashboardDateRange = .thirtyDays
    var usesCustomDateRange = false
    var onOpenTrade: ((TradeID) -> Void)? = nil
    var onOpenRule: ((TradingRulesComplianceAnalytics.RuleID) -> Void)? = nil
    var onOpenDay: ((String) -> Void)? = nil

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var impactExpanded = false
    @State private var timelineExpanded = false
    @State private var trendsExpanded = false
    @State private var showsAllViolations = false
    @State private var mostBrokenListExpanded = false
    @State private var worstDaysListExpanded = false
    @State private var recurringPatternsListExpanded = false
    @State private var ruleImpactDetailsExpanded = false

    private static let violationPreviewCount = 5
    /// Initial row count on the dedicated Trading Rules Analytics page (full data unchanged).
    private static let analyticsCompactListCount = 3

    private enum MetricCopy {
        static let complianceScore = (
            title: "Compliance score",
            body: "Adherence % = rules followed ÷ (followed + violations) among checks we could evaluate. Unevaluated checks are excluded and never counted as compliant."
        )
        static let unevaluated = (
            title: "Unevaluated",
            body: "Checks we could not run with reliable data, such as missing session, symbol, R:R, contracts, risk, or psychology timing (for example loss exit time). They are excluded from adherence and never counted as followed or violated."
        )
        static let violations = (
            title: "Violations",
            body: "Each violation is a failed rule check at trade, day, or week level using the rules effective for that moment, including retrospective scoring when enabled."
        )
        static let trends = (
            title: "Compliance trends",
            body: "Each bar is compliance % for that week or month: rules followed ÷ evaluable checks in your dashboard scope. Faded bars mean too little data for that period."
        )
        static let impact = (
            title: "Rule impact",
            body: "Realized P&L per trade grouped by whether each trade-level rule check was followed or violated. Commissions and fees are not always included. Day and week aggregate checks are excluded. Each side needs at least 5 priced trades to show comparisons (a display threshold, not statistical proof). Correlation only."
        )
    }

    var body: some View {
        Group {
            switch presentation {
            case .compactCollapsible:
                compactBody
            case .freeOverview:
                if let analytics {
                    complianceOverviewBlock(analytics, showsDisciplineExtras: false)
                }
            case .expandedAnalyticsPage:
                if let analytics {
                    expandedAnalyticsContent(analytics)
                }
            }
        }
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            Text("Trading rules")
                .font(.headline)
                .foregroundStyle(colors.primaryText)

            if let analytics, analytics.score.evaluated > 0 {
                collapsibleContent(analytics)
            } else {
                Text("Configure rules in Settings and log trades with the data each rule needs. Missing fields stay unevaluated.")
                    .experienceStyle(.caption, color: colors.secondaryText)
            }
        }
        .padding(ExperienceSpacing.md)
        .experienceTradingRulesCard(prominence: .standard)
    }

    // MARK: - Expanded analytics page

    @ViewBuilder
    private func expandedAnalyticsContent(_ analytics: TradingRulesComplianceAnalytics.Result) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xl) {
            complianceOverviewBlock(analytics, showsDisciplineExtras: true)
            actionableInsightsBlock(analytics)
            complianceTrendsBlock(analytics)
            violationPatternsSection(analytics)
            ruleImpactSection(analytics)
            violationsBlock(analytics)
        }
        .sheet(isPresented: $showsAllViolations) {
            TradingRulesViolationsTimelineSheet(
                violations: analytics.violations,
                onOpenTrade: { tradeID in
                    showsAllViolations = false
                    onOpenTrade?(tradeID)
                }
            )
        }
    }

    // MARK: - Redesigned analytics sections

    @ViewBuilder
    private func complianceOverviewBlock(
        _ analytics: TradingRulesComplianceAnalytics.Result,
        showsDisciplineExtras: Bool = true
    ) -> some View {
        let score = analytics.score
        let progress = analytics.disciplineProgress
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            AnalyticsSectionHeader(
                title: "Compliance overview",
                infoTitle: MetricCopy.complianceScore.title,
                infoBody: MetricCopy.complianceScore.body,
                infoAccessibilityID: "tradingRulesAnalytics.score.info"
            )

            VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                Text(score.adherencePercent.map { "\($0, specifier: "%.1f")%" } ?? "–")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(colors.primaryText)

                adherenceProgressBar(percent: score.adherencePercent)

                HStack(spacing: ExperienceSpacing.xs) {
                    statTile(title: "Followed", value: score.followed, tone: colors.profit, showsInfo: false)
                    statTile(title: "Violations", value: score.violated, tone: score.violated > 0 ? colors.loss : colors.secondaryText, showsInfo: false)
                    statTile(
                        title: "Unevaluated",
                        value: score.unevaluated,
                        tone: colors.secondaryText,
                        showsInfo: true,
                        infoTitle: MetricCopy.unevaluated.title,
                        infoBody: MetricCopy.unevaluated.body,
                        infoID: "tradingRulesAnalytics.unevaluated.info"
                    )
                }

                if showsDisciplineExtras, !progress.insufficientData {
                    HStack(spacing: ExperienceSpacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Discipline goal \(Int(progress.goalPercent))%")
                                .experienceStyle(.caption2, color: colors.tertiaryText)
                            Text("\(progress.daysMeetingGoal)/\(progress.evaluatedDaysInScope) days")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(colors.primaryText)
                        }
                        Spacer(minLength: 0)
                        if progress.periodCompareSufficient, let delta = progress.adherenceDeltaPoints {
                            Text(String(format: "%+.1f pts vs prior", delta))
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(delta >= 0 ? colors.profit : colors.loss)
                        }
                    }
                }

                if showsDisciplineExtras {
                    retrospectiveStatusLine(analytics)
                }

                if score.evaluated == 0, let hint = zeroEvalHint, !hint.isEmpty {
                    Text(hint)
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                        .lineLimit(3)
                }
            }
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .experienceTradingRulesCard(prominence: .featured)
        }
    }

    @ViewBuilder
    private func actionableInsightsBlock(_ analytics: TradingRulesComplianceAnalytics.Result) -> some View {
        let broken = analytics.violationPatterns.mostBrokenRules.filter { $0.violated > 0 }
        let topBroken = broken.first
        let insightPreview = Array(personalInsights.prefix(2))

        if insightPreview.isEmpty, topBroken == nil {
            EmptyView()
        } else {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            AnalyticsSectionHeader(
                title: "Actionable insights",
                infoTitle: "Actionable insights",
                infoBody: "Highest-signal recommendations from your scoped compliance and discipline patterns.",
                infoAccessibilityID: "tradingRulesAnalytics.actionable.info"
            )

            VStack(spacing: ExperienceSpacing.xs) {
                ForEach(insightPreview) { item in
                    actionableInsightRow(item)
                }
                if let topBroken {
                    Button {
                        onOpenRule?(topBroken.ruleID)
                    } label: {
                        HStack(spacing: ExperienceSpacing.sm) {
                            Image(systemName: "exclamationmark.shield.fill")
                                .foregroundStyle(colors.loss)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Worst rule: \(topBroken.ruleLabel)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(colors.primaryText)
                                    .lineLimit(2)
                                Text("\(topBroken.violated) violations in scope")
                                    .experienceStyle(.caption2, color: colors.secondaryText)
                            }
                            Spacer(minLength: 0)
                            if onOpenRule != nil {
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(colors.tertiaryText)
                            }
                        }
                        .padding(ExperienceSpacing.md)
                        .experienceTradingRulesCard(prominence: .standard)
                    }
                    .buttonStyle(.plain)
                    .disabled(onOpenRule == nil)
                }
            }
        }
        }
    }

    @ViewBuilder
    private func actionableInsightRow(_ item: DashboardInsightItem) -> some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            Image(systemName: "lightbulb.fill")
                .font(.caption)
                .foregroundStyle(colors.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                    .lineLimit(2)
                Text(item.displayBody)
                    .experienceStyle(.caption2, color: colors.secondaryText)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(ExperienceSpacing.md)
        .experienceTradingRulesCard(prominence: .standard)
    }

    @ViewBuilder
    private func complianceTrendsBlock(_ analytics: TradingRulesComplianceAnalytics.Result) -> some View {
        let progress = analytics.disciplineProgress
        let showDaily = activeDateRange == .sevenDays
            || activeDateRange == .thirtyDays
            || (usesCustomDateRange && analytics.weeklyTrend.count <= 2)
        let showMonthly = activeDateRange != .sevenDays
        let dailySeries = progress.historyPoints.map {
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
        }
        let weeklySeries = showDaily && !dailySeries.isEmpty ? dailySeries : analytics.weeklyTrend

        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            AnalyticsSectionHeader(
                title: "Trends",
                infoTitle: MetricCopy.trends.title,
                infoBody: MetricCopy.trends.body,
                infoAccessibilityID: "tradingRulesAnalytics.trends.info"
            )

            TradingRulesComplianceTrendCharts(
                weekly: weeklySeries,
                monthly: showMonthly ? analytics.monthlyTrend : [],
                layout: .compact
            )
        }
    }

    @ViewBuilder
    private func violationPatternsSection(_ analytics: TradingRulesComplianceAnalytics.Result) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            AnalyticsSectionHeader(
                title: "Violation patterns",
                infoTitle: "Violation patterns",
                infoBody: "Where rules break most often, on which days, and which habits repeat.",
                infoAccessibilityID: "tradingRulesAnalytics.patterns.info"
            )
            expandedViolationPatterns(analytics)
        }
    }

    @ViewBuilder
    private func ruleImpactSection(_ analytics: TradingRulesComplianceAnalytics.Result) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            AnalyticsSectionHeader(
                title: "Rule impact",
                infoTitle: MetricCopy.impact.title,
                infoBody: MetricCopy.impact.body,
                infoAccessibilityID: "tradingRulesAnalytics.impact.info"
            )
            TradingRulesRuleImpactHighlightStrip(
                highlights: analytics.impactHighlights,
                onOpenRule: onOpenRule
            )
            if ruleImpactDetailsExpanded {
                ruleImpactExpandedContent(analytics)
            } else if !impactDisplayRows(analytics).isEmpty {
                Button("Show per-rule impact") {
                    ruleImpactDetailsExpanded = true
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(colors.accent)
            }
        }
    }


    @ViewBuilder
    private func complianceScoreBlock(_ analytics: TradingRulesComplianceAnalytics.Result) -> some View {
        let score = analytics.score
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            AnalyticsSectionHeader(
                title: "Compliance score",
                infoTitle: MetricCopy.complianceScore.title,
                infoBody: MetricCopy.complianceScore.body,
                infoAccessibilityID: "tradingRulesAnalytics.score.info"
            )

            VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                Text(score.adherencePercent.map { "\($0, specifier: "%.1f")%" } ?? "–")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(colors.primaryText)

                adherenceProgressBar(percent: score.adherencePercent)

                HStack(spacing: ExperienceSpacing.xs) {
                    statTile(title: "Followed", value: score.followed, tone: colors.profit, showsInfo: false)
                    statTile(title: "Violations", value: score.violated, tone: score.violated > 0 ? colors.loss : colors.secondaryText, showsInfo: false)
                    statTile(
                        title: "Unevaluated",
                        value: score.unevaluated,
                        tone: colors.secondaryText,
                        showsInfo: true,
                        infoTitle: MetricCopy.unevaluated.title,
                        infoBody: MetricCopy.unevaluated.body,
                        infoID: "tradingRulesAnalytics.unevaluated.info"
                    )
                }

                retrospectiveStatusLine(analytics)

                if score.evaluated == 0, let hint = zeroEvalHint, !hint.isEmpty {
                    Text(hint)
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                        .lineLimit(2)
                }
            }
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .experienceTradingRulesCard(prominence: .standard)
        }
    }

    @ViewBuilder
    private func retrospectiveStatusLine(_ analytics: TradingRulesComplianceAnalytics.Result) -> some View {
        let parts = retrospectiveStatusParts(analytics)
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .lineLimit(2)
        }
    }

    private func retrospectiveStatusParts(_ analytics: TradingRulesComplianceAnalytics.Result) -> [String] {
        var parts: [String] = []
        if analytics.retrospectivelyEvaluatedTrades > 0 {
            let n = analytics.retrospectivelyEvaluatedTrades
            parts.append("Retroactive: \(n) trade\(n == 1 ? "" : "s") with current rules")
        }
        if analytics.usesHistoricalRevisions {
            parts.append("Saved rule history for later trades")
        }
        return parts
    }

    @ViewBuilder
    private func adherenceProgressBar(percent: Double?) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(colors.fillSecondary.opacity(0.6))
                if let percent {
                    let fraction = CGFloat(percent / 100)
                    Capsule()
                        .fill(colors.profit.opacity(0.9))
                        .frame(width: max(0, proxy.size.width * min(1, fraction)))
                }
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Compliance progress")
        .accessibilityValue(percent.map { "\($0, specifier: "%.1f") percent" } ?? "No data")
    }

    @ViewBuilder
    private func statTile(
        title: String,
        value: Int,
        tone: Color,
        showsInfo: Bool,
        infoTitle: String? = nil,
        infoBody: String? = nil,
        infoID: String? = nil
    ) -> some View {
        VStack(spacing: ExperienceSpacing.xxs) {
            HStack(spacing: 2) {
                Text(title)
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if showsInfo, let infoTitle, let infoBody {
                    AnalyticsMetricInfoButton(
                        title: infoTitle,
                        bodyText: infoBody,
                        accessibilityID: infoID
                    )
                }
            }
            Text("\(value)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tone)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ExperienceSpacing.sm)
        .padding(.horizontal, ExperienceSpacing.xs)
        .experienceDashboardNestedCard(cornerRadius: ExperienceRadius.sm)
    }

    // MARK: - Violation patterns (expanded page)

    @ViewBuilder
    private func expandedViolationPatterns(_ analytics: TradingRulesComplianceAnalytics.Result) -> some View {
        let patterns = analytics.violationPatterns
        let brokenWithViolations = patterns.mostBrokenRules.filter { $0.violated > 0 }

        VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
            if brokenWithViolations.isEmpty {
                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    AnalyticsSectionHeader(
                        title: "Most broken rules",
                        infoTitle: "Most broken rules",
                        infoBody: "Ranked by violation rate among evaluated checks (followed + violated). Unevaluated field gaps are excluded. Counts are checks, not unique trades.",
                        infoAccessibilityID: "tradingRulesAnalytics.mostBroken.info"
                    )
                    Text("No rule violations in this scope.")
                        .experienceStyle(.caption, color: colors.secondaryText)
                }
            } else {
                mostBrokenRulesBlock(brokenWithViolations)
            }

            worstTradingDaysBlock(patterns.worstTradingDays)

            recurringPatternsBlock(patterns.recurringPatterns)
        }
    }

    /// Compact dashboard embed.
    @ViewBuilder
    private func violationPatternsBlock(_ analytics: TradingRulesComplianceAnalytics.Result) -> some View {
        expandedViolationPatterns(analytics)
    }

    @ViewBuilder
    private func mostBrokenRulesBlock(_ rows: [TradingRulesViolationPatterns.MostBrokenRuleRow]) -> some View {
        let visible = visibleAnalyticsRows(rows, isExpanded: mostBrokenListExpanded)
        let hasMore = rows.count > Self.analyticsCompactListCount

        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            AnalyticsSectionHeader(
                title: "Most broken rules",
                infoTitle: "Most broken rules",
                infoBody: "Ranked by violation rate among evaluated checks (followed + violated). Unevaluated field gaps are excluded. Counts are checks, not unique trades.",
                infoAccessibilityID: "tradingRulesAnalytics.mostBroken.info"
            )
            VStack(spacing: ExperienceSpacing.xs) {
                ForEach(visible) { row in
                    mostBrokenRuleCard(row)
                }
            }
            analyticsListExpandButton(
                isExpanded: mostBrokenListExpanded,
                hasMore: hasMore,
                accessibilityID: "tradingRulesAnalytics.mostBroken.showMore"
            ) {
                mostBrokenListExpanded.toggle()
            }
        }
    }

    @ViewBuilder
    private func mostBrokenRuleCard(_ row: TradingRulesViolationPatterns.MostBrokenRuleRow) -> some View {
        let tappable = onOpenRule != nil
        Button {
            onOpenRule?(row.ruleID)
        } label: {
            HStack(spacing: ExperienceSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.ruleLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                        .lineLimit(2)
                    Text("\(row.violated) violations · \(row.evaluated) checks")
                        .experienceStyle(.caption2, color: colors.secondaryText)
                }
                Spacer(minLength: 0)
                if let rate = row.violationRatePercent {
                    Text("\(rate, specifier: "%.1f")%")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(colors.loss)
                }
                if tappable {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(colors.tertiaryText)
                }
            }
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .experienceTradingRulesCard(prominence: .standard)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!tappable)
        .accessibilityLabel(row.accessibilitySummary)
    }

    @ViewBuilder
    private func worstTradingDaysBlock(_ rows: [TradingRulesViolationPatterns.WorstTradingDayRow]) -> some View {
        let visible = visibleAnalyticsRows(rows, isExpanded: worstDaysListExpanded)
        let hasMore = rows.count > Self.analyticsCompactListCount

        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            AnalyticsSectionHeader(
                title: "Worst trading days",
                infoTitle: "Worst trading days",
                infoBody: "Top days by violation rate among Eastern trading days with at least \(TradingRulesViolationPatterns.worstDayMinimumEvaluatedChecks) evaluated checks in scope.",
                infoAccessibilityID: "tradingRulesAnalytics.worstDays.info"
            )
            if rows.isEmpty {
                Text("No days with enough evaluated checks to rank yet.")
                    .experienceStyle(.caption, color: colors.secondaryText)
            } else {
                VStack(spacing: ExperienceSpacing.xs) {
                    ForEach(visible) { row in
                        worstTradingDayCard(row)
                    }
                }
                analyticsListExpandButton(
                    isExpanded: worstDaysListExpanded,
                    hasMore: hasMore,
                    accessibilityID: "tradingRulesAnalytics.worstDays.showMore"
                ) {
                    worstDaysListExpanded.toggle()
                }
            }
        }
    }

    @ViewBuilder
    private func worstTradingDayCard(_ row: TradingRulesViolationPatterns.WorstTradingDayRow) -> some View {
        let tappable = onOpenDay != nil
        Button {
            onOpenDay?(row.dayKey)
        } label: {
            HStack(spacing: ExperienceSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.displayDate)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                    Text("\(row.violated) violations · \(row.evaluated) checks")
                        .experienceStyle(.caption2, color: colors.secondaryText)
                }
                Spacer(minLength: 0)
                Text("\(row.violationRatePercent, specifier: "%.1f")%")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(colors.loss)
                if tappable {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(colors.tertiaryText)
                }
            }
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .experienceTradingRulesCard(prominence: .standard)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!tappable)
    }

    @ViewBuilder
    private func recurringPatternsBlock(_ patterns: [TradingRulesViolationPatterns.RecurringPatternSummary]) -> some View {
        let visible = visibleAnalyticsRows(patterns, isExpanded: recurringPatternsListExpanded)
        let hasMore = patterns.count > Self.analyticsCompactListCount

        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            AnalyticsSectionHeader(
                title: "Recurring patterns",
                infoTitle: "Recurring patterns",
                infoBody: "Rules violated on multiple evaluated trading days in your recent history. Based on checks, not calendar days.",
                infoAccessibilityID: "tradingRulesAnalytics.recurring.info"
            )
            if patterns.isEmpty {
                Text("No recurring violation patterns in this scope.")
                    .experienceStyle(.caption, color: colors.secondaryText)
            } else {
                VStack(spacing: ExperienceSpacing.xs) {
                    ForEach(visible) { item in
                        Text(item.summary)
                            .experienceStyle(.subheadline, color: colors.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(ExperienceSpacing.md)
                            .experienceTradingRulesCard(prominence: .standard)
                    }
                }
                analyticsListExpandButton(
                    isExpanded: recurringPatternsListExpanded,
                    hasMore: hasMore,
                    accessibilityID: "tradingRulesAnalytics.recurring.showMore"
                ) {
                    recurringPatternsListExpanded.toggle()
                }
            }
        }
    }

    private func visibleAnalyticsRows<Element>(_ rows: [Element], isExpanded: Bool) -> [Element] {
        guard !isExpanded, rows.count > Self.analyticsCompactListCount else { return rows }
        return Array(rows.prefix(Self.analyticsCompactListCount))
    }

    @ViewBuilder
    private func analyticsListExpandButton(
        isExpanded: Bool,
        hasMore: Bool,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        if hasMore {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    action()
                }
            } label: {
                HStack(spacing: ExperienceSpacing.xxs) {
                    Text(isExpanded ? "Show Less" : "Show More")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.secondaryText)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(colors.tertiaryText)
                }
                .padding(.vertical, ExperienceSpacing.xxs)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(accessibilityID)
            .accessibilityLabel(isExpanded ? "Show Less" : "Show More")
        }
    }

    // MARK: - Violations

    @ViewBuilder
    private func violationsBlock(_ analytics: TradingRulesComplianceAnalytics.Result) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack {
                AnalyticsSectionHeader(
                    title: "Violation history",
                    infoTitle: MetricCopy.violations.title,
                    infoBody: MetricCopy.violations.body,
                    infoAccessibilityID: "tradingRulesAnalytics.violations.info"
                )
                Spacer(minLength: 0)
                if analytics.violations.count > Self.violationPreviewCount {
                    Button("View all") {
                        showsAllViolations = true
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.accent)
                }
            }

            if analytics.violations.isEmpty {
                Text("No violations in this scope.")
                    .experienceStyle(.caption, color: colors.secondaryText)
            } else {
                let preview = Array(analytics.violations.prefix(Self.violationPreviewCount))
                VStack(spacing: 0) {
                    ForEach(Array(preview.enumerated()), id: \.element.id) { index, event in
                        TradingRulesViolationEventRow(event: event, onOpenTrade: onOpenTrade)
                        if index < preview.count - 1 {
                            ExperienceDivider()
                                .padding(.leading, 36)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func violationRow(_ event: TradingRulesComplianceAnalytics.ViolationEvent) -> some View {
        let canOpen = event.tradeID != nil && onOpenTrade != nil
        Button {
            guard canOpen, let raw = event.tradeID else { return }
            onOpenTrade?(TradeID(raw))
        } label: {
            HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(colors.loss)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.ruleLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                        .lineLimit(1)
                    Text(event.summary)
                        .experienceStyle(.caption2, color: colors.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: ExperienceSpacing.xs)

                Text(compactViolationDate(event))
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                    .monospacedDigit()

                if canOpen {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(colors.tertiaryText)
                }
            }
            .padding(.vertical, ExperienceSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canOpen)
        .accessibilityHint(canOpen ? "Opens trade detail" : "")
    }

    private func compactViolationDate(_ event: TradingRulesComplianceAnalytics.ViolationEvent) -> String {
        TradingRulesViolationFormat.display.string(from: event.at)
    }

    // MARK: - Rule impact (expanded)

    @ViewBuilder
    private func ruleImpactExpandedContent(_ analytics: TradingRulesComplianceAnalytics.Result) -> some View {
        let rows = impactDisplayRows(analytics)
        if rows.isEmpty {
            Text("Not enough priced trades yet.")
                .experienceStyle(.caption, color: colors.secondaryText)
        } else {
            VStack(spacing: ExperienceSpacing.xs) {
                ForEach(rows) { row in
                    TradingRulesRuleImpactCard(row: row, onOpenRule: onOpenRule)
                }
            }
        }
    }

    private func impactDisplayRows(
        _ analytics: TradingRulesComplianceAnalytics.Result
    ) -> [TradingRulesComplianceAnalytics.ImpactRow] {
        analytics.impacts.filter { $0.followed.priced + $0.violated.priced > 0 }
    }

    // MARK: - Compact / collapsible (dashboard-style preview)

    @ViewBuilder
    private func collapsibleContent(_ analytics: TradingRulesComplianceAnalytics.Result) -> some View {
        legacyScoreCard(analytics.score)

        disclosure(
            title: "Rule impact",
            expanded: $impactExpanded,
            trailing: impactExpanded ? "Hide" : "Show"
        ) {
            legacyRuleImpactContent(analytics)
        }

        disclosure(
            title: "Compliance trends",
            expanded: $trendsExpanded,
            trailing: trendsExpanded ? "Hide" : "Show"
        ) {
            TradingRulesComplianceTrendCharts(
                weekly: analytics.weeklyTrend,
                monthly: analytics.monthlyTrend,
                layout: .standard
            )
        }

        disclosure(
            title: "Violation timeline",
            expanded: $timelineExpanded,
            trailing: "\(analytics.violations.count) events"
        ) {
            legacyViolationTimelineContent(analytics)
        }
    }

    private func legacyScoreCard(_ score: TradingRulesComplianceAnalytics.Score) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Compliance score")
                .experienceStyle(.caption2, color: colors.accent)
                .textCase(.uppercase)
            Text(score.adherencePercent.map { "\($0, specifier: "%.1f")%" } ?? "–")
                .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
            HStack {
                legacyStatChip("Followed", value: score.followed, tone: colors.profit)
                legacyStatChip("Violations", value: score.violated, tone: colors.loss)
                legacyStatChip("Unevaluated", value: score.unevaluated, tone: colors.secondaryText)
            }
            Text(score.explanation)
                .experienceStyle(.caption2, color: colors.tertiaryText)
        }
    }

    @ViewBuilder
    private func legacyRuleImpactContent(_ analytics: TradingRulesComplianceAnalytics.Result) -> some View {
        Text("Compares priced trades when a rule was followed vs violated (≥5 priced per side). Correlations only.")
            .experienceStyle(.caption2, color: colors.tertiaryText)
        let rows = analytics.impacts.filter(\.sufficientSample)
        if rows.isEmpty {
            Text("Not enough priced trades in both groups yet.")
                .experienceStyle(.caption, color: colors.secondaryText)
        } else {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text(row.ruleLabel)
                        .font(.subheadline.weight(.semibold))
                    if let summary = row.summary {
                        Text(summary)
                            .experienceStyle(.caption, color: colors.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(ExperienceSpacing.sm)
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md))
            }
        }
    }

    @ViewBuilder
    private func legacyViolationTimelineContent(_ analytics: TradingRulesComplianceAnalytics.Result) -> some View {
        if analytics.violations.isEmpty {
            Text("No violations in this scope.")
                .experienceStyle(.caption, color: colors.secondaryText)
        } else {
            ForEach(analytics.violations.prefix(30)) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(event.ruleLabel) · \(event.dayKey)")
                        .font(.caption.weight(.semibold))
                    Text(event.summary)
                        .experienceStyle(.caption2, color: colors.secondaryText)
                    if let tradeID = event.tradeID, let onOpenTrade {
                        Button("Open trade") {
                            onOpenTrade(TradeID(tradeID))
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, ExperienceSpacing.xxs)
            }
        }
    }

    private func legacyStatChip(_ title: String, value: Int, tone: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).experienceStyle(.caption2, color: colors.tertiaryText)
            Text("\(value)").font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(tone)
        }
        .frame(maxWidth: .infinity)
    }

    private func disclosure<Content: View>(
        title: String,
        expanded: Binding<Bool>,
        trailing: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Button {
                expanded.wrappedValue.toggle()
            } label: {
                HStack {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(trailing).experienceStyle(.caption, color: colors.secondaryText)
                }
            }
            .buttonStyle(.plain)
            if expanded.wrappedValue {
                content()
            }
        }
    }
}

// MARK: - Violations sheet

private struct TradingRulesViolationsTimelineSheet: View {
    let violations: [TradingRulesComplianceAnalytics.ViolationEvent]
    let onOpenTrade: (TradeID) -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(violations) { event in
                    Group {
                        if let tradeID = event.tradeID {
                            Button {
                                dismiss()
                                onOpenTrade(TradeID(tradeID))
                            } label: {
                                violationLabel(event)
                            }
                        } else {
                            violationLabel(event)
                        }
                    }
                    .experienceDashboardListRow()
                }
            }
            .experiencePlainListStyle()
            .experienceNavigationTitle("All violations")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .experienceAnalyticsSheetChrome()
    }

    @ViewBuilder
    private func violationLabel(_ event: TradingRulesComplianceAnalytics.ViolationEvent) -> some View {
        HStack(spacing: ExperienceSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(colors.loss)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.ruleLabel)
                    .font(.subheadline.weight(.semibold))
                Text(event.summary)
                    .experienceStyle(.caption2, color: colors.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(TradingRulesViolationFormat.display.string(from: event.at))
                .experienceStyle(.caption2, color: colors.tertiaryText)
        }
    }
}
