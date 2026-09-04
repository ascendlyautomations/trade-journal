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

            ProfileStatsDashboardSection(title: "Trading Sessions", accessibilityID: "profile.stats.sessions") {
                ProfileStatsDashboardCard {
                    ProfileStatsSessionsCard(
                        sessionTotal: metrics.sessionTotal,
                        sessions: metrics.sessionBreakdown
                    )
                }
            }

            performanceSection(metrics)
            winnerLoserSection(metrics)
            extremesSection(metrics)
            directionSection(metrics)
            streaksSection(metrics)
        }
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
            value: viewModel.selectedMode
        )
    }

    // MARK: - Dashboard sections

    private func performanceSection(_ metrics: ProfileStatisticsMetrics.Result) -> some View {
        let valueAreaHeight: CGFloat = 62
        return ProfileStatsDashboardSection(title: "Performance", accessibilityID: "profile.stats.performance") {
            ProfileStatsDashboardCard {
                HStack(alignment: .center, spacing: ExperienceSpacing.xxs) {
                    ProfileStatsMetricCard(
                        value: Self.factorText(metrics.profitFactor),
                        label: "Profit Factor",
                        valueColor: profitFactorColor(metrics.profitFactor),
                        valueAreaHeight: valueAreaHeight
                    )
                    ProfileStatsWinRateCard(
                        winRate: metrics.winRate,
                        formattedWinRate: ProfileDisplay.formatWinRate(metrics.winRate),
                        valueAreaHeight: valueAreaHeight
                    )
                    ProfileStatsMetricCard(
                        value: Self.currencyText(metrics.profitPerTrade),
                        label: "P / Trade",
                        valueColor: profitPerTradeColor(metrics.profitPerTrade),
                        valueAreaHeight: valueAreaHeight
                    )
                }
            }
        }
    }

    private func winnerLoserSection(_ metrics: ProfileStatisticsMetrics.Result) -> some View {
        ProfileStatsDashboardSection(title: "Winner vs Loser", accessibilityID: "profile.stats.trading") {
            ProfileStatsDashboardCard {
                ProfileStatsWinnerLoserCard(
                    averageWinner: metrics.averageWinner,
                    averageLoser: metrics.averageLoser,
                    winnerText: Self.currencyText(metrics.averageWinner),
                    loserText: Self.currencyText(metrics.averageLoser),
                    ratioText: Self.winLossRatioText(
                        winner: metrics.averageWinner,
                        loser: metrics.averageLoser
                    )
                )
            }
        }
    }

    private func extremesSection(_ metrics: ProfileStatisticsMetrics.Result) -> some View {
        ProfileStatsDashboardSection(title: "Extremes", accessibilityID: "profile.stats.extremes") {
            HStack(spacing: ExperienceSpacing.xs) {
                ProfileStatsExtremeCard(
                    title: "Best Trade",
                    value: Self.positivePnlText(metrics.biggestWin),
                    direction: .up,
                    tone: colors.profit
                )
                ProfileStatsExtremeCard(
                    title: "Worst Trade",
                    value: metrics.biggestLoss.map { Self.pnlCurrencyText($0) } ?? "—",
                    direction: .down,
                    tone: metrics.biggestLoss == nil ? colors.primaryText : colors.loss
                )
            }
        }
    }

    private func directionSection(_ metrics: ProfileStatisticsMetrics.Result) -> some View {
        ProfileStatsDashboardSection(title: "Direction", accessibilityID: "profile.stats.activity") {
            ProfileStatsDashboardCard {
                ProfileStatsLongShortCard(
                    longCount: metrics.longTrades,
                    shortCount: max(0, metrics.filteredTradeCount - metrics.longTrades)
                )
            }
        }
    }

    private func streaksSection(_ metrics: ProfileStatisticsMetrics.Result) -> some View {
        ProfileStatsDashboardSection(title: "Streaks", accessibilityID: "profile.stats.streaks") {
            HStack(spacing: ExperienceSpacing.xs) {
                ProfileStatsStreakCard(
                    title: "Best Win Streak",
                    count: metrics.maxWinStreak,
                    symbol: "🔥",
                    tone: metrics.maxWinStreak > 0 ? colors.profit : colors.primaryText
                )
                ProfileStatsStreakCard(
                    title: "Largest Loss Streak",
                    count: metrics.maxLossStreak,
                    symbol: "",
                    tone: metrics.maxLossStreak > 0 ? colors.loss : colors.primaryText
                )
            }
        }
    }

    private var modeFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ExperienceSpacing.xs) {
                ForEach(ProfileStatisticsMetrics.Mode.profileFilterCases) { mode in
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

    private func profitFactorColor(_ value: Decimal?) -> Color {
        guard let value else { return colors.primaryText }
        return value >= 1 ? colors.profit : colors.loss
    }

    private func profitPerTradeColor(_ value: Decimal?) -> Color {
        guard let value else { return colors.primaryText }
        return value >= 0 ? colors.profit : colors.loss
    }

    // MARK: - Formatting (web parity)

    static func currencyText(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return signedCurrency(value, minFraction: 0, maxFraction: 2)
    }

    static func pnlCurrencyText(_ value: Decimal) -> String {
        signedCurrency(value, minFraction: 2, maxFraction: 2)
    }

    static func positivePnlText(_ value: Decimal) -> String {
        let text = pnlCurrencyText(value)
        return value > 0 ? "+\(text)" : text
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

    static func winLossRatioText(winner: Decimal?, loser: Decimal?) -> String {
        guard let winner, let loser else { return "—" }
        let lossMagnitude = abs(NSDecimalNumber(decimal: loser).doubleValue)
        guard lossMagnitude > 0 else { return "—" }
        let ratio = NSDecimalNumber(decimal: winner).doubleValue / lossMagnitude
        return String(format: "%.2fx", ratio)
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
