import SwiftUI

enum TradingRulesRuleImpactFormat {
    static func signedMoney(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = abs(value) >= 100 ? 0 : 2
        formatter.positivePrefix = formatter.plusSign + (formatter.currencySymbol ?? "$")
        formatter.negativePrefix = formatter.minusSign + (formatter.currencySymbol ?? "$")
        return formatter.string(from: NSNumber(value: value)) ?? (value >= 0 ? "+$\(value)" : "-$\(abs(value))")
    }

    static func percentPoints(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return String(format: "%@%.1f pts", sign, value)
    }

    static func optionalFactor(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(format: "%.2f", value)
    }

    static func optionalRr(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(format: "%.2fR", value)
    }
}

struct TradingRulesRuleImpactHighlightStrip: View {
    let highlights: [TradingRulesRuleImpact.ComparisonHighlight]
    var showsTitle: Bool = true
    var onOpenRule: ((TradingRulesComplianceAnalytics.RuleID) -> Void)?

    @Environment(\.themeColors) private var colors

    var body: some View {
        if !highlights.isEmpty {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                if showsTitle {
                    Text("Largest avg P&L differences")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                }
                Text("Correlation only, not proof that following or violating caused the outcome. Requires 5+ priced trades per side.")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                ForEach(highlights) { item in
                    Button {
                        onOpenRule?(item.ruleID)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.ruleLabel)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(colors.primaryText)
                                Text("Win rate Δ \(TradingRulesRuleImpactFormat.percentPoints(item.winRateDeltaPoints))")
                                    .experienceStyle(.caption2, color: colors.secondaryText)
                            }
                            Spacer(minLength: 0)
                            Text(TradingRulesRuleImpactFormat.signedMoney(item.avgPnlDelta))
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(performanceColor(item.avgPnlDelta))
                            if onOpenRule != nil {
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(colors.tertiaryText)
                            }
                        }
                        .padding(ExperienceSpacing.sm)
                        .experienceTradingRulesCard(prominence: .standard)
                    }
                    .buttonStyle(.plain)
                    .disabled(onOpenRule == nil)
                }
            }
        }
    }

    private func performanceColor(_ value: Double) -> Color {
        if value > 0 { return colors.profit }
        if value < 0 { return colors.loss }
        return colors.secondaryText
    }
}

struct TradingRulesRuleImpactCard: View {
    let row: TradingRulesComplianceAnalytics.ImpactRow
  var onOpenRule: ((TradingRulesComplianceAnalytics.RuleID) -> Void)?

    @Environment(\.themeColors) private var colors
    @State private var moreMetricsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack {
                Text(row.ruleLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                Spacer(minLength: 0)
                if row.sufficientSample, let delta = row.avgPnlDelta {
                    Text(TradingRulesRuleImpactFormat.signedMoney(delta))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(performanceColor(delta))
                }
                if onOpenRule != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(colors.tertiaryText)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard onOpenRule != nil else { return }
                onOpenRule?(row.ruleID)
            }

            if row.followed.priced + row.violated.priced == 0 {
                Text("No priced trades linked to this rule yet.")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            } else if row.sufficientSample {
                HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                    sideColumn(title: "Followed", side: row.followed)
                    sideColumn(title: "Violated", side: row.violated)
                }
                if let winDelta = row.winRateDeltaPoints {
                    Text("Win rate difference (followed − violated): \(TradingRulesRuleImpactFormat.percentPoints(winDelta))")
                        .experienceStyle(.caption2, color: colors.secondaryText)
                }
            } else {
                insufficientCopy
            }

            if row.followed.priced > 0 || row.violated.priced > 0 {
                DisclosureGroup(isExpanded: $moreMetricsExpanded) {
                    if row.sufficientSample {
                        moreMetricsGrid
                    } else {
                        insufficientCopy
                    }
                } label: {
                    Text("More metrics")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.accent)
                }
                .tint(colors.accent)
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceTradingRulesCard(prominence: .standard)
    }

    @ViewBuilder
    private var insufficientCopy: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Need 5+ priced trades on each side to compare groups.")
                .experienceStyle(.caption2, color: colors.tertiaryText)
            Text("Followed: \(row.followed.priced) priced · Violated: \(row.violated.priced) priced")
                .experienceStyle(.caption2, color: colors.secondaryText)
        }
    }

    @ViewBuilder
    private func sideColumn(title: String, side: TradingRulesComplianceAnalytics.ImpactSide) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .experienceStyle(.caption2, color: colors.tertiaryText)
            if side.priced == 0 {
                Text("–")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(colors.secondaryText)
            } else {
                Text("Avg realized P&L")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                Text(TradingRulesRuleImpactFormat.signedMoney(side.avgNetPnl ?? 0))
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(performanceColor(side.avgNetPnl ?? 0))
                let winPct = Int((side.winRateFraction ?? 0) * 100)
                Text("Win rate \(winPct)%")
                    .experienceStyle(.caption2, color: colors.secondaryText)
                Text("\(side.priced) priced trades")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var moreMetricsGrid: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            metricPair(label: "Total realized P&L") {
                followedViolatedText(
                    followed: TradingRulesRuleImpactFormat.signedMoney(row.followed.totalNetPnl),
                    violated: TradingRulesRuleImpactFormat.signedMoney(row.violated.totalNetPnl),
                    followsPerformanceColor: true
                )
            }
            metricPair(label: "Profit factor") {
                followedViolatedText(
                    followed: TradingRulesRuleImpactFormat.optionalFactor(row.followed.profitFactor),
                    violated: TradingRulesRuleImpactFormat.optionalFactor(row.violated.profitFactor),
                    followsPerformanceColor: false
                )
            }
            metricPair(label: "Expectancy") {
                followedViolatedText(
                    followed: row.followed.expectancy.map { TradingRulesRuleImpactFormat.signedMoney($0) } ?? "–",
                    violated: row.violated.expectancy.map { TradingRulesRuleImpactFormat.signedMoney($0) } ?? "–",
                    followsPerformanceColor: true
                )
            }
            metricPair(label: "Avg realized R:R") {
                followedViolatedText(
                    followed: TradingRulesRuleImpactFormat.optionalRr(row.followed.avgRealizedRr),
                    violated: TradingRulesRuleImpactFormat.optionalRr(row.violated.avgRealizedRr),
                    followsPerformanceColor: false
                )
            }
            Text("Based on trade-level checks using Trade.realizedP&L (commissions/fees may not be included). Day/week aggregate checks are excluded from financial impact.")
                .experienceStyle(.caption2, color: colors.tertiaryText)
        }
        .padding(.top, ExperienceSpacing.xs)
    }

    @ViewBuilder
    private func metricPair(label: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .experienceStyle(.caption2, color: colors.tertiaryText)
            value()
        }
    }

    @ViewBuilder
    private func followedViolatedText(followed: String, violated: String, followsPerformanceColor: Bool) -> some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Followed")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                Text(followed)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(followsPerformanceColor ? performanceColorFromText(followed) : colors.secondaryText)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Violated")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                Text(violated)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(followsPerformanceColor ? performanceColorFromText(violated) : colors.secondaryText)
            }
            Spacer(minLength: 0)
        }
    }

    private func performanceColor(_ value: Double) -> Color {
        if value > 0 { return colors.profit }
        if value < 0 { return colors.loss }
        return colors.secondaryText
    }

    private func performanceColorFromText(_ text: String) -> Color {
        if text.hasPrefix("+") || (text.contains("$") && !text.hasPrefix("-") && text != "–") {
            if text.hasPrefix("-") { return colors.loss }
            if text == "–" { return colors.secondaryText }
            return colors.profit
        }
        if text.hasPrefix("-") { return colors.loss }
        return colors.secondaryText
    }
}

struct TradingRulesRuleImpactDetailSection: View {
    let row: TradingRulesComplianceAnalytics.ImpactRow
    var onOpenTrade: ((TradeID) -> Void)?

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            Text("Financial impact")
                .font(.headline)
                .foregroundStyle(colors.primaryText)
            Text("Trade-level outcomes only. Correlation, not causation.")
                .experienceStyle(.caption2, color: colors.tertiaryText)

            TradingRulesRuleImpactCard(row: row, onOpenRule: nil)
        }
    }
}
