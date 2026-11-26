import SwiftUI

// MARK: - Chart planning

enum PsychologyReportChartPlanner {
    static func sectionIDs(for template: PsychologyReportTemplate) -> [String] {
        switch template {
        case .weekly, .monthly, .custom:
            return [
                "discipline", "sleep", "emotion", "afterLosses", "stress",
                "tradeFrequency", "focus", "energy",
            ]
        case .sleepPerformance:
            return ["sleep", "sleepQuality"]
        case .discipline:
            return ["discipline"]
        case .emotions:
            return ["emotion"]
        case .afterLosses:
            return ["afterLosses", "afterLossesWait"]
        case .mentalState:
            return ["stress", "focus", "energy", "morning"]
        case .tradeFrequency:
            return ["tradeFrequency"]
        }
    }

    static func resolvedComparisonSections(for report: PsychologyReport) -> [PsychologyAnalyticsSection] {
        let wanted = sectionIDs(for: report.periodRef.template)
        let byID = Dictionary(uniqueKeysWithValues: report.analyticsSections.map { ($0.id, $0) })
        var resolved: [PsychologyAnalyticsSection] = []
        for id in wanted {
            guard let section = byID[id], sectionIsChartable(section) else { continue }
            resolved.append(section)
        }
        if report.periodRef.template.isPeriodic, resolved.count > 3 {
            return Array(resolved.prefix(3))
        }
        return resolved
    }

    static func sectionIsChartable(_ section: PsychologyAnalyticsSection) -> Bool {
        guard section.groups.count >= 2 else { return false }
        return section.groups.allSatisfy { $0.metrics.tradeCount >= PsychologyComparisonBuilder.advancedMinimumTrades }
    }

    static func primaryInsight(for report: PsychologyReport) -> PsychologyInsightCard? {
        let preferred: PsychologyInsightCategory? = {
            switch report.periodRef.template {
            case .sleepPerformance: return .sleep
            case .discipline: return .discipline
            case .emotions: return .emotion
            case .afterLosses: return .afterLosses
            case .mentalState: return .mentalState
            case .tradeFrequency: return .tradeFrequency
            case .weekly, .monthly, .custom: return nil
            }
        }()
        if let preferred,
           let match = report.insightCards.first(where: { $0.category == preferred }) {
            return match
        }
        return report.insightCards.first
    }

    static func showsEmotionBreakdown(for report: PsychologyReport) -> Bool {
        switch report.periodRef.template {
        case .emotions, .weekly, .monthly, .custom:
            return report.emotionBreakdown.contains { $0.metrics.tradeCount >= 1 }
        default:
            return false
        }
    }

    static func chartExplanation(for section: PsychologyAnalyticsSection) -> String? {
        section.footnote
    }
}

// MARK: - Coverage

struct PsychologyReportCoverageCard: View {
    let report: PsychologyReport

    @Environment(\.themeColors) private var colors

    var body: some View {
        Text(dataCoverageLine)
            .experienceStyle(.footnote, color: colors.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ExperienceSpacing.md)
            .modifier(ReportDetailInsetSurface(cornerRadius: ExperienceRadius.sm))
    }

    private var dataCoverageLine: String {
        var parts: [String] = [
            "\(NumberDisplay.integer(report.performance.tradeCount)) trades",
        ]
        if report.matchedDayCount > 0 {
            parts.append("\(NumberDisplay.integer(report.matchedDayCount)) matched check-in days")
        }
        if report.planTaggedTradeCount > 0 {
            parts.append("\(NumberDisplay.integer(report.planTaggedTradeCount)) with plan tags")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Performance metrics (footer)

struct PsychologyReportPerformanceMetricsCard: View {
    let report: PsychologyReport

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Performance")
                .experienceStyle(.headline, color: colors.primaryText)
            metricsGrid
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(cornerRadius: ExperienceRadius.card)
        .accessibilityIdentifier("psychologyReport.performanceMetrics")
    }

    private var metricsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: ExperienceSpacing.sm),
                GridItem(.flexible(), spacing: ExperienceSpacing.sm),
            ],
            spacing: ExperienceSpacing.sm
        ) {
            metricCell(
                "Net P&L",
                TraderPsychologyAnalyticsEngine.optionalMoney(
                    report.performance.totalPnL == 0 && report.performance.tradeCount == 0
                        ? nil
                        : report.performance.totalPnL
                ) ?? "–",
                tone: pnlTone(report.performance.totalPnL)
            )
            metricCell(
                "Win Rate",
                TraderPsychologyAnalyticsEngine.formatWinRate(report.performance.winRate)
            )
            metricCell(
                "Avg Trade",
                TraderPsychologyAnalyticsEngine.optionalMoney(report.performance.averagePnL) ?? "–",
                tone: report.performance.averagePnL.map { pnlTone($0) }
            )
            metricCell(
                "Profit Factor",
                report.performance.profitFactor.map { NumberDisplay.ratio($0, fractionDigits: 2) } ?? "–"
            )
        }
    }

    private func metricCell(_ label: String, _ value: String, tone: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .tracking(0.4)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(tone ?? colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.backgroundSecondary.opacity(0.65), in: RoundedRectangle(
            cornerRadius: ExperienceRadius.sm,
            style: .continuous
        ))
    }

    private func pnlTone(_ value: Decimal) -> Color {
        if value > 0 { return colors.profit }
        if value < 0 { return colors.loss }
        return colors.primaryText
    }
}

// MARK: - Primary insight

struct PsychologyReportPrimaryInsightCard: View {
    let card: PsychologyInsightCard

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.sectionTitle)
                    .experienceStyle(.caption2, color: colors.accent)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
                Text(card.reliability.label)
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            }
            Text(card.displayHeadline)
                .experienceStyle(.subheadline, color: colors.primaryText)
                .fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)
            Text(card.displayDetail)
                .experienceStyle(.footnote, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(NumberDisplay.integer(card.sampleSize)) trades in sample")
                .experienceStyle(.caption2, color: colors.tertiaryText)
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(cornerRadius: ExperienceRadius.card)
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        }
    }
}

// MARK: - Charts section

struct PsychologyReportChartsSection: View {
    let report: PsychologyReport

    @Environment(\.themeColors) private var colors

    var body: some View {
        let sections = PsychologyReportChartPlanner.resolvedComparisonSections(for: report)
        let showEmotions = PsychologyReportChartPlanner.showsEmotionBreakdown(for: report)
        let showPlan = report.periodRef.template == .discipline
            || (report.periodRef.template.isPeriodic && report.planTaggedTradeCount >= PsychologyComparisonBuilder.advancedMinimumTrades)

        if sections.isEmpty, !showEmotions, !showPlan, report.comparisons.isEmpty {
            insufficientDataCard
        } else {
            VStack(alignment: .leading, spacing: ReportDetailLayout.sectionSpacing) {
                ForEach(sections) { section in
                    comparisonChartCard(section)
                }

                if showEmotions {
                    emotionBreakdownCard
                }

                if showPlan {
                    planAdherenceCard
                }

                if report.periodRef.template == .monthly, !report.comparisons.isEmpty {
                    PsychologyReportMonthlyComparisonsView(comparisons: report.comparisons)
                }
            }
        }
    }

    private var insufficientDataCard: some View {
        chartCard(title: "Psychology comparisons") {
            DashboardChartEmptyCopy(
                message: emptyMessage(for: report.periodRef.template)
            )
        }
    }

    private func emptyMessage(for template: PsychologyReportTemplate) -> String {
        switch template {
        case .mentalState, .sleepPerformance:
            return "Complete daily check-ins on trading days to unlock these comparisons."
        case .emotions:
            return "Tag emotions on trades to see how each label lines up with results."
        case .discipline:
            return "Mark whether you followed your plan on trades to compare on-plan vs off-plan."
        default:
            return "Log more trades in this period to unlock reliable psychology charts."
        }
    }

    private func comparisonChartCard(_ section: PsychologyAnalyticsSection) -> some View {
        chartCard(title: section.title, subtitle: section.subtitle) {
            PsychologyReportABComparisonChart(section: section)
            if let explanation = PsychologyReportChartPlanner.chartExplanation(for: section) {
                Text(explanation)
                    .experienceStyle(.footnote, color: colors.tertiaryText)
                    .padding(.top, ExperienceSpacing.xs)
            }
        }
    }

    private var emotionBreakdownCard: some View {
        chartCard(title: "Emotions", subtitle: "Avg P&L and win rate by tag") {
            PsychologyReportEmotionBarsView(rows: report.emotionBreakdown)
        }
    }

    private var planAdherenceCard: some View {
        chartCard(title: "Plan adherence", subtitle: planAdherenceSubtitle) {
            PsychologyReportPlanAdherenceView(report: report)
        }
    }

    private var planAdherenceSubtitle: String? {
        guard let rate = report.tradingPsychology.followedPlanRate else { return nil }
        return "\(NumberDisplay.percent(rate * 100, minimumFractionDigits: 0, maximumFractionDigits: 0)) followed plan (\(NumberDisplay.integer(report.planTaggedTradeCount)) tagged)"
    }

    @ViewBuilder
    private func chartCard(title: String, subtitle: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .experienceStyle(.headline, color: colors.primaryText)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .experienceStyle(.footnote, color: colors.tertiaryText)
                }
            }
            content()
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceDashboardCard(cornerRadius: ExperienceRadius.card)
    }
}

// MARK: - A/B comparison chart

struct PsychologyReportABComparisonChart: View {
    let section: PsychologyAnalyticsSection

    @Environment(\.themeColors) private var colors

    private struct BarRow: Identifiable {
        var id: String
        var label: String
        var avgPnL: Double
        var winRate: Decimal?
        var tradeCount: Int
        var highlight: Bool
    }

    private var rows: [BarRow] {
        section.groups.map { group in
            BarRow(
                id: group.id,
                label: group.label,
                avgPnL: group.metrics.averagePnL.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0,
                winRate: group.metrics.winRate,
                tradeCount: group.metrics.tradeCount,
                highlight: group.highlight
            )
        }
    }

    private var maxAbs: Double {
        max(rows.map { abs($0.avgPnL) }.max() ?? 0, 1)
    }

    var body: some View {
        if !PsychologyReportChartPlanner.sectionIsChartable(section) {
            DashboardChartEmptyCopy(message: "Need at least \(PsychologyComparisonBuilder.advancedMinimumTrades) trades on each side for a fair comparison.")
        } else {
            ProposedWidthClamp {
                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.label)
                                    .experienceStyle(.caption, color: row.highlight ? colors.accent : colors.secondaryText)
                                    .fontWeight(row.highlight ? .semibold : .regular)
                                Spacer(minLength: 8)
                                Text(signedMoney(row.avgPnL))
                                    .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                                    .foregroundStyle(toneColor(row.avgPnL))
                                Text("· \(row.tradeCount)")
                                    .experienceStyle(.caption2, color: colors.tertiaryText)
                            }
                            GeometryReader { geo in
                                let width = row.avgPnL == 0
                                    ? 0
                                    : max(8, geo.size.width * CGFloat(abs(row.avgPnL) / maxAbs))
                                HStack(spacing: 0) {
                                    if row.avgPnL < 0 {
                                        Spacer(minLength: 0)
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(colors.loss.opacity(row.highlight ? 0.95 : 0.75))
                                            .frame(width: width, height: 10)
                                    } else {
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(colors.profit.opacity(row.highlight ? 0.95 : 0.75))
                                            .frame(width: width, height: 10)
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                            .frame(height: 10)
                            if row.tradeCount >= PsychologyComparisonBuilder.advancedMinimumTrades,
                               let winRate = row.winRate {
                                Text("\(TraderPsychologyAnalyticsEngine.formatWinRate(winRate)) win rate")
                                    .experienceStyle(.caption2, color: colors.tertiaryText)
                            }
                        }
                    }
                }
            }
        }
    }

    private func toneColor(_ value: Double) -> Color {
        if value > 0.01 { return colors.profit }
        if value < -0.01 { return colors.loss }
        return colors.secondaryText
    }

    private func signedMoney(_ value: Double) -> String {
        NumberDisplay.chartSignedCurrency(value)
    }
}

// MARK: - Emotion bars

struct PsychologyReportEmotionBarsView: View {
    let rows: [PsychologyReportEmotionRow]

    @Environment(\.themeColors) private var colors

    private var displayRows: [PsychologyReportEmotionRow] {
        Array(rows.prefix(6))
    }

    var body: some View {
        if displayRows.isEmpty {
            DashboardChartEmptyCopy(message: "Tag emotions on trades to see performance by label.")
        } else {
            let maxAbs = max(
                displayRows.compactMap { $0.metrics.averagePnL.map { abs(NSDecimalNumber(decimal: $0).doubleValue) } }.max() ?? 0,
                1
            )
            ProposedWidthClamp {
                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    ForEach(displayRows) { row in
                        emotionRow(row, maxAbs: maxAbs)
                    }
                }
            }
        }
    }

    private func emotionRow(_ row: PsychologyReportEmotionRow, maxAbs: Double) -> some View {
        let avg = row.metrics.averagePnL.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.label)
                    .experienceStyle(.caption, color: colors.secondaryText)
                Spacer(minLength: 8)
                if row.metrics.tradeCount >= PsychologyComparisonBuilder.advancedMinimumTrades {
                    Text(signedMoney(avg))
                        .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(toneColor(avg))
                } else {
                    Text("Early signal")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                }
                Text("· \(row.metrics.tradeCount)")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            }
            if row.metrics.tradeCount >= PsychologyComparisonBuilder.advancedMinimumTrades {
                GeometryReader { geo in
                    let width = avg == 0 ? 0 : max(8, geo.size.width * CGFloat(abs(avg) / maxAbs))
                    HStack(spacing: 0) {
                        if avg < 0 {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(colors.loss.opacity(0.85))
                                .frame(width: width, height: 10)
                        } else {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(colors.profit.opacity(0.85))
                                .frame(width: width, height: 10)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(height: 10)
                if let winRate = row.metrics.winRate {
                    Text("\(TraderPsychologyAnalyticsEngine.formatWinRate(winRate)) win rate")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                }
            }
        }
    }

    private func toneColor(_ value: Double) -> Color {
        if value > 0.01 { return colors.profit }
        if value < -0.01 { return colors.loss }
        return colors.secondaryText
    }

    private func signedMoney(_ value: Double) -> String {
        NumberDisplay.chartSignedCurrency(value)
    }
}

// MARK: - Plan adherence

struct PsychologyReportPlanAdherenceView: View {
    let report: PsychologyReport

    @Environment(\.themeColors) private var colors

    private var disciplineSection: PsychologyAnalyticsSection? {
        report.analyticsSections.first { $0.id == "discipline" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            if let rate = report.tradingPsychology.followedPlanRate,
               report.planTaggedTradeCount >= PsychologyComparisonBuilder.advancedMinimumTrades {
                HStack(spacing: ExperienceSpacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("On plan")
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                        Text(NumberDisplay.percent(rate * 100, minimumFractionDigits: 0, maximumFractionDigits: 0))
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(colors.primaryText)
                    }
                    Spacer(minLength: 0)
                    if let off = offPlanRate(rate) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Off plan")
                                .experienceStyle(.caption2, color: colors.tertiaryText)
                            Text(NumberDisplay.percent(off * 100, minimumFractionDigits: 0, maximumFractionDigits: 0))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(colors.secondaryText)
                        }
                    }
                }
            }

            if let section = disciplineSection,
               PsychologyReportChartPlanner.sectionIsChartable(section) {
                PsychologyReportABComparisonChart(section: section)
            } else if report.planTaggedTradeCount < PsychologyComparisonBuilder.advancedMinimumTrades {
                DashboardChartEmptyCopy(message: "Mark plan adherence on at least \(PsychologyComparisonBuilder.advancedMinimumTrades) trades to compare on-plan vs off-plan.")
            }
        }
    }

    private func offPlanRate(_ followed: Double) -> Double? {
        guard followed >= 0, followed <= 1 else { return nil }
        return 1 - followed
    }
}

// MARK: - Monthly comparisons

struct PsychologyReportMonthlyComparisonsView: View {
    let comparisons: [PsychologyReportComparison]

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Month-over-month")
                .experienceStyle(.headline, color: colors.primaryText)
            ForEach(comparisons, id: \.headline) { item in
                HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                    Image(systemName: trendSymbol(item.headline))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(trendColor(item.headline))
                        .frame(width: 22, height: 22)
                        .background(trendColor(item.headline).opacity(0.15), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.headline)
                            .experienceStyle(.subheadline, color: colors.primaryText)
                            .fontWeight(.semibold)
                        Text(item.detail)
                            .experienceStyle(.footnote, color: colors.secondaryText)
                        Text(item.reliability)
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                    }
                }
                .padding(ExperienceSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .experienceDashboardNestedCard(cornerRadius: ExperienceRadius.sm)
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(ReportDetailSectionSurface())
    }

    private func trendSymbol(_ headline: String) -> String {
        let lower = headline.lowercased()
        if lower.contains("improved") || lower.contains("increased") {
            return "arrow.up.right"
        }
        if lower.contains("slipped") || lower.contains("decreased") || lower.contains("declined") {
            return "arrow.down.right"
        }
        return "arrow.left.arrow.right"
    }

    private func trendColor(_ headline: String) -> Color {
        let lower = headline.lowercased()
        if lower.contains("improved") || lower.contains("increased") {
            return colors.success
        }
        if lower.contains("slipped") || lower.contains("decreased") || lower.contains("declined") {
            return colors.warning
        }
        return colors.accent
    }
}

// MARK: - Condensed bullets

struct PsychologyReportBulletStrip: View {
    let title: String
    let items: [String]
    let tint: Color

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text(title)
                .experienceStyle(.headline, color: colors.primaryText)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                    Circle().fill(tint).frame(width: 6, height: 6).padding(.top, 6)
                    Text(item)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        }
    }
}