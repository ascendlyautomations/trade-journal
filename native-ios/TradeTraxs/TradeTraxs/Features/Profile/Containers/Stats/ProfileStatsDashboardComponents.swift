import SwiftUI

// MARK: - Section chrome

struct ProfileStatsDashboardSection<Content: View>: View {
    let title: String
    let accessibilityID: String
    @ViewBuilder var content: () -> Content

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text(title)
                .font(.system(.caption, design: .default).weight(.semibold))
                .foregroundStyle(colors.secondaryText)
                .textCase(.uppercase)
                .tracking(0.4)
                .padding(.horizontal, ExperienceSpacing.xxs)
                .accessibilityAddTraits(.isHeader)

            content()
        }
        .accessibilityIdentifier(accessibilityID)
    }
}

struct ProfileStatsDashboardCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @Environment(\.themeColors) private var colors

    var body: some View {
        content()
            .padding(ExperienceSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                colors.fillSecondary.opacity(0.55),
                in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
            )
    }
}

// MARK: - Performance metric cards

struct ProfileStatsMetricCard: View {
    let value: String
    let label: String
    var valueColor: Color?
    var valueAreaHeight: CGFloat?

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(valueColor ?? colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: valueAreaHeight, alignment: .center)
            Text(label)
                .font(.system(.caption2, design: .default).weight(.medium))
                .foregroundStyle(colors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ExperienceSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }
}

struct ProfileStatsWinRateCard: View {
    let winRate: Decimal?
    let formattedWinRate: String
    var valueAreaHeight: CGFloat = 62

    @Environment(\.themeColors) private var colors

    private let ringLineWidth: CGFloat = 3
    private var textInset: CGFloat { ringLineWidth * 2 + 10 }
    private var ringSize: CGFloat { valueAreaHeight }

    private var progress: CGFloat {
        guard let winRate else { return 0 }
        let rate = NSDecimalNumber(decimal: winRate).doubleValue
        return CGFloat(min(max(rate, 0), 1))
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(colors.fillSecondary, lineWidth: ringLineWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        colors.profit,
                        style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text(formattedWinRate)
                    .font(.system(.caption, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(colors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: ringSize - textInset, height: ringSize - textInset)
                    .multilineTextAlignment(.center)
            }
            .frame(width: ringSize, height: ringSize)

            Text("Win Rate")
                .font(.system(.caption2, design: .default).weight(.medium))
                .foregroundStyle(colors.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ExperienceSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Win Rate, \(formattedWinRate)")
    }
}

// MARK: - Winner vs loser comparison

struct ProfileStatsWinnerLoserCard: View {
    let averageWinner: Decimal?
    let averageLoser: Decimal?
    let winnerText: String
    let loserText: String
    let ratioText: String

    @Environment(\.themeColors) private var colors

    private var scaleMax: Double {
        let winner = NSDecimalNumber(decimal: averageWinner ?? 0).doubleValue
        let loser = abs(NSDecimalNumber(decimal: averageLoser ?? 0).doubleValue)
        return max(winner, loser, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            comparisonRow(
                title: "Avg Winner",
                value: winnerText,
                fill: colors.profit,
                fraction: barFraction(for: averageWinner, absolute: false)
            )
            comparisonRow(
                title: "Avg Loser",
                value: loserText,
                fill: colors.loss,
                fraction: barFraction(for: averageLoser, absolute: true)
            )

            HStack {
                Text("Avg Win / Avg Loss")
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(colors.secondaryText)
                Spacer(minLength: ExperienceSpacing.sm)
                Text(ratioText)
                    .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(colors.primaryText)
            }
            .padding(.top, 2)
        }
        .accessibilityElement(children: .contain)
    }

    private func barFraction(for value: Decimal?, absolute: Bool) -> CGFloat {
        guard let value else { return 0 }
        let raw = NSDecimalNumber(decimal: value).doubleValue
        let magnitude = absolute ? abs(raw) : max(raw, 0)
        guard magnitude > 0 else { return 0 }
        return CGFloat(min(max(magnitude / scaleMax, 0.06), 1))
    }

    private func comparisonRow(
        title: String,
        value: String,
        fill: Color,
        fraction: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(.subheadline, design: .default))
                    .foregroundStyle(colors.primaryText)
                Spacer(minLength: ExperienceSpacing.sm)
                Text(value)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(fill)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(colors.fillSecondary)
                    Capsule()
                        .fill(fill.opacity(0.9))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

// MARK: - Trade extremes

struct ProfileStatsExtremeCard: View {
    enum Direction {
        case up, down
    }

    let title: String
    let value: String
    let direction: Direction
    var tone: Color

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            HStack(spacing: 4) {
                Image(systemName: direction == .up ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tone)
                Text(title)
                    .font(.system(.caption2, design: .default).weight(.semibold))
                    .foregroundStyle(colors.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.3)
            }
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ExperienceSpacing.sm)
        .background(
            colors.fillSecondary.opacity(0.55),
            in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

// MARK: - Long vs short split

struct ProfileStatsLongShortCard: View {
    let longCount: Int
    let shortCount: Int

    @Environment(\.themeColors) private var colors

    private var total: Int { max(longCount + shortCount, 0) }

    private var longFraction: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(longCount) / CGFloat(total)
    }

    private var longPercentText: String {
        guard total > 0 else { return "—" }
        return String(format: "%.0f%%", Double(longCount) / Double(total) * 100)
    }

    private var shortPercentText: String {
        guard total > 0 else { return "—" }
        return String(format: "%.0f%%", Double(shortCount) / Double(total) * 100)
    }

    var body: some View {
        VStack(spacing: ExperienceSpacing.xs) {
            HStack {
                directionColumn(title: "Long", count: longCount, alignment: .leading)
                Spacer(minLength: ExperienceSpacing.sm)
                directionColumn(title: "Short", count: shortCount, alignment: .trailing)
            }

            GeometryReader { geo in
                let width = geo.size.width
                let longWidth = width * longFraction
                HStack(spacing: 2) {
                    if longCount > 0 {
                        Capsule()
                            .fill(colors.profit.opacity(0.85))
                            .frame(width: max(longWidth - 1, 6))
                    }
                    if shortCount > 0 {
                        Capsule()
                            .fill(colors.accent.opacity(0.85))
                            .frame(maxWidth: .infinity)
                    }
                    if total == 0 {
                        Capsule().fill(colors.fillSecondary)
                    }
                }
            }
            .frame(height: 10)

            HStack {
                Text(longPercentText)
                    .font(.system(.caption2, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(colors.secondaryText)
                Spacer()
                Text(shortPercentText)
                    .font(.system(.caption2, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(colors.secondaryText)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Long \(longCount) trades, \(longPercentText). Short \(shortCount) trades, \(shortPercentText)")
    }

    private func directionColumn(title: String, count: Int, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(.system(.caption2, design: .default).weight(.semibold))
                .foregroundStyle(colors.secondaryText)
                .textCase(.uppercase)
            Text("\(count)")
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(colors.primaryText)
        }
    }
}

// MARK: - Streak cards

struct ProfileStatsStreakCard: View {
    let title: String
    let count: Int
    let symbol: String
    var tone: Color

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if !symbol.isEmpty {
                    Text(symbol)
                        .font(.system(.caption, design: .default))
                }
                Text(title)
                    .font(.system(.caption2, design: .default).weight(.semibold))
                    .foregroundStyle(colors.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Text("\(count)")
                .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(tone)
            Text(count == 1 ? "trade" : "trades")
                .font(.system(.caption2, design: .default))
                .foregroundStyle(colors.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ExperienceSpacing.sm)
        .background(
            colors.fillSecondary.opacity(0.55),
            in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count) trades")
    }
}

// MARK: - Trading sessions

struct ProfileStatsSessionsCard: View {
    let sessionTotal: Int
    let sessions: [ProfileStatisticsMetrics.SessionRow]

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            if sessionTotal > 0 {
                Text("\(sessionTotal) trades tagged")
                    .experienceStyle(.caption2, color: colors.secondaryText)
            }

            if sessions.isEmpty {
                Text("Add session tags to trades to unlock this breakdown.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            } else {
                VStack(spacing: ExperienceSpacing.sm) {
                    ForEach(sessions) { row in
                        sessionRow(row)
                    }
                }
            }
        }
    }

    private func sessionRow(_ row: ProfileStatisticsMetrics.SessionRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.label)
                    .font(.system(.subheadline, design: .default).weight(.medium))
                    .foregroundStyle(colors.primaryText)
                Spacer()
                Text("\(Int(row.pct.rounded()))%")
                    .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(colors.primaryText)
                Text("·")
                    .foregroundStyle(colors.tertiaryText)
                Text("\(row.count)")
                    .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(colors.secondaryText)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(colors.fillSecondary)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [colors.accent.opacity(0.9), colors.profit.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geo.size.width * CGFloat(max(0.04, min(1, row.pct / 100)))
                        )
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.label), \(Int(row.pct.rounded())) percent, \(row.count) trades")
    }
}
