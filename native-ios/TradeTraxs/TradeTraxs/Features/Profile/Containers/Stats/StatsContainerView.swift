import SwiftUI

struct StatsContainerView: View {
    @Bindable var viewModel: StatsContainerViewModel

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ProfileSectionContainerChrome(
            section: .stats,
            state: viewModel.state,
            onRetry: { Task { await viewModel.refresh() } }
        ) {
            if let metrics = viewModel.metrics {
                content(metrics)
            }
        }
    }

    @ViewBuilder
    private func content(_ metrics: ProfileStatisticsMetrics.Result) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            modeFilter

            if let message = viewModel.filterEmptyMessage {
                Text(message)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .accessibilityIdentifier("profile.stats.filterEmpty")
            }

            equityBlock(metrics)
            sessionsBlock(metrics)

            groupedSection(title: "Performance", accessibilityID: "profile.stats.performance") {
                metricRow(
                    label: "Profit Factor",
                    value: Self.factorText(metrics.profitFactor),
                    tone: profitFactorTone(metrics.profitFactor)
                )
                sectionDivider
                metricRow(
                    label: "Win %",
                    value: ProfileDisplay.formatWinRate(metrics.winRate),
                    tone: .neutral
                )
                sectionDivider
                metricRow(
                    label: "Payouts",
                    value: ProfileDisplay.formatMoney(viewModel.payoutTotal),
                    tone: viewModel.payoutTotal == nil ? .neutral : .positive
                )
                sectionDivider
                metricRow(
                    label: "Profit / Trade",
                    value: Self.currencyText(metrics.profitPerTrade),
                    tone: profitPerTradeTone(metrics.profitPerTrade)
                )
            }

            groupedSection(title: "Trading", accessibilityID: "profile.stats.trading") {
                metricRow(
                    label: "Avg Winner",
                    value: Self.currencyText(metrics.averageWinner),
                    tone: metrics.averageWinner == nil ? .neutral : .positive
                )
                sectionDivider
                metricRow(
                    label: "Avg Loser",
                    value: Self.currencyText(metrics.averageLoser),
                    tone: metrics.averageLoser == nil ? .neutral : .negative
                )
                sectionDivider
                metricRow(
                    label: "Biggest Win",
                    value: Self.pnlCurrencyText(metrics.biggestWin),
                    tone: .positive
                )
                sectionDivider
                metricRow(
                    label: "Biggest Loss",
                    value: metrics.biggestLoss.map { Self.pnlCurrencyText($0) } ?? "—",
                    tone: metrics.biggestLoss == nil ? .neutral : .negative
                )
            }

            groupedSection(title: "Activity", accessibilityID: "profile.stats.activity") {
                metricRow(
                    label: "Long Trades",
                    value: "\(metrics.longTrades)",
                    tone: .neutral
                )
                sectionDivider
                metricRow(
                    label: "Short Trades",
                    value: "\(max(0, metrics.filteredTradeCount - metrics.longTrades))",
                    tone: .neutral
                )
                sectionDivider
                metricRow(
                    label: "Largest Win Streak",
                    value: "W\(metrics.maxWinStreak)",
                    tone: metrics.maxWinStreak > 0 ? .positive : .neutral
                )
                sectionDivider
                metricRow(
                    label: "Largest Loss Streak",
                    value: "L\(metrics.maxLossStreak)",
                    tone: metrics.maxLossStreak > 0 ? .negative : .neutral
                )
            }
        }
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
            value: viewModel.selectedMode
        )
    }

    private var modeFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ExperienceSpacing.xs) {
                ForEach(ProfileStatisticsMetrics.Mode.allCases) { mode in
                    ExperienceChip(
                        title: mode.title,
                        isSelected: viewModel.selectedMode == mode
                    ) {
                        viewModel.setMode(mode)
                    }
                    .accessibilityIdentifier("profile.stats.mode.\(mode.rawValue)")
                }
            }
        }
        .accessibilityLabel("Account mode filter")
    }

    // MARK: - Grouped sections (Settings / Health style)

    private func groupedSection(
        title: String,
        accessibilityID: String,
        @ViewBuilder rows: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text(title)
                .font(.system(.caption, design: .default).weight(.semibold))
                .foregroundStyle(colors.secondaryText)
                .textCase(.uppercase)
                .tracking(0.4)
                .padding(.horizontal, ExperienceSpacing.xxs)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                rows()
            }
            .background(
                colors.fillSecondary.opacity(0.55),
                in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
            )
        }
        .accessibilityIdentifier(accessibilityID)
    }

    private func metricRow(label: String, value: String, tone: MetricTone) -> some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            Text(label)
                .font(.system(.subheadline, design: .default))
                .foregroundStyle(colors.primaryText)
                .lineLimit(1)
            Spacer(minLength: ExperienceSpacing.sm)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(toneColor(tone))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(colors.separator.opacity(0.55))
            .frame(height: ExperienceBorder.hairline)
            .padding(.leading, ExperienceSpacing.md)
    }

    private func sessionsBlock(_ metrics: ProfileStatisticsMetrics.Result) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Trading Sessions")
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                Spacer()
                Text(
                    metrics.sessionTotal > 0
                        ? "\(metrics.sessionTotal) trades tagged"
                        : "No session data"
                )
                .experienceStyle(.caption2, color: colors.secondaryText)
            }

            if metrics.sessionBreakdown.isEmpty {
                Text("Add session tags to trades to unlock this breakdown.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            } else {
                VStack(spacing: ExperienceSpacing.sm) {
                    ForEach(metrics.sessionBreakdown) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.label)
                                    .font(.system(.subheadline, design: .default))
                                    .foregroundStyle(colors.primaryText)
                                Spacer()
                                Text("\(Int(row.pct.rounded()))%")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                                    .foregroundStyle(colors.primaryText)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(colors.fillSecondary)
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [colors.accent, colors.profit],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(
                                            width: geo.size.width * CGFloat(
                                                max(0.04, min(1, row.pct / 100))
                                            )
                                        )
                                }
                            }
                            .frame(height: 10)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            colors.fillSecondary.opacity(0.55),
            in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
        )
        .accessibilityIdentifier("profile.stats.sessions")
    }

    private func equityBlock(_ metrics: ProfileStatisticsMetrics.Result) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Equity Curve")
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                Spacer()
                if metrics.filteredTradeCount > 0 {
                    Text(Self.equityMoneyText(metrics.currentEquity))
                        .font(.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(metrics.currentEquity >= 0 ? colors.profit : colors.loss)
                }
            }

            ProfileEquityCurveView(points: metrics.equityData)
                .frame(height: 180)
                .accessibilityLabel("Equity curve")
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            colors.fillSecondary.opacity(0.55),
            in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
        )
        .accessibilityIdentifier("profile.stats.equity")
    }

    private func toneColor(_ tone: MetricTone) -> Color {
        switch tone {
        case .positive: return colors.profit
        case .negative: return colors.loss
        case .neutral: return colors.primaryText
        }
    }

    private func profitFactorTone(_ value: Decimal?) -> MetricTone {
        guard let value else { return .neutral }
        return value >= 1 ? .positive : .negative
    }

    private func profitPerTradeTone(_ value: Decimal?) -> MetricTone {
        guard let value else { return .neutral }
        return value >= 0 ? .positive : .negative
    }

    // MARK: - Formatting (web parity)

    static func currencyText(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return signedCurrency(value, minFraction: 0, maxFraction: 2)
    }

    static func pnlCurrencyText(_ value: Decimal) -> String {
        signedCurrency(value, minFraction: 2, maxFraction: 2)
    }

    static func equityMoneyText(_ value: Decimal) -> String {
        signedCurrency(value, minFraction: 2, maxFraction: 2)
    }

    static func factorText(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        let number = NSDecimalNumber(decimal: value)
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal
        return formatter.string(from: number) ?? "\(value)"
    }

    private static func signedCurrency(
        _ value: Decimal,
        minFraction: Int,
        maxFraction: Int
    ) -> String {
        let absValue = abs(value)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = minFraction
        formatter.maximumFractionDigits = maxFraction
        formatter.usesGroupingSeparator = true
        let body = formatter.string(from: NSDecimalNumber(decimal: absValue)) ?? "\(absValue)"
        return value < 0 ? "-$\(body)" : "$\(body)"
    }
}

private enum MetricTone {
    case positive, negative, neutral
}
