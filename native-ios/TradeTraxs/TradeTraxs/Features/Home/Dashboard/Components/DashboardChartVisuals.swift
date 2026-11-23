import Charts
import SwiftUI

// MARK: - Win / Loss ring

struct DashboardWinLossRingView: View {
    let winCount: Int
    let lossCount: Int
    var onSelectWins: (() -> Void)?
    var onSelectLosses: (() -> Void)?

    @Environment(\.themeColors) private var colors

    private var total: Int { winCount + lossCount }
    private var winRate: Double {
        guard total > 0 else { return 0 }
        return Double(winCount) / Double(total)
    }

    var body: some View {
        Group {
            if total == 0 {
                DashboardChartEmptyCopy(
                    message: "Close a few trades to unlock your win / loss breakdown."
                )
            } else {
                HStack(spacing: ExperienceSpacing.lg) {
                    ZStack {
                        Chart {
                            SectorMark(
                                angle: .value("Wins", max(winCount, 0)),
                                innerRadius: .ratio(0.62),
                                angularInset: 1.5
                            )
                            .foregroundStyle(colors.profit)
                            .cornerRadius(3)

                            SectorMark(
                                angle: .value("Losses", max(lossCount, 0)),
                                innerRadius: .ratio(0.62),
                                angularInset: 1.5
                            )
                            .foregroundStyle(colors.loss)
                            .cornerRadius(3)
                        }
                        .frame(width: 132, height: 132)
                        .accessibilityHidden(true)

                        VStack(spacing: 2) {
                            Text(NumberDisplay.percent(winRate * 100, minimumFractionDigits: 0, maximumFractionDigits: 0))
                                .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                                .foregroundStyle(colors.primaryText)
                                .contentTransition(.numericText())
                            Text("Win rate")
                                .experienceStyle(.caption2, color: colors.tertiaryText)
                        }
                    }

                    VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                        legendButton(
                            symbol: "W",
                            title: "Wins",
                            value: NumberDisplay.integer(winCount),
                            color: colors.profit,
                            action: onSelectWins
                        )
                        legendButton(
                            symbol: "L",
                            title: "Losses",
                            value: NumberDisplay.integer(lossCount),
                            color: colors.loss,
                            action: onSelectLosses
                        )
                        Text("\(NumberDisplay.integer(total)) closed outcomes")
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    private func legendButton(
        symbol: String,
        title: String,
        value: String,
        color: Color,
        action: (() -> Void)?
    ) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: ExperienceSpacing.sm) {
                Text(symbol)
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(color)
                    .frame(width: 22, height: 22)
                    .background(color.opacity(0.18), in: Circle())
                Text(title)
                    .experienceStyle(.callout, color: colors.secondaryText)
                Spacer(minLength: 0)
                Text(value)
                    .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(colors.primaryText)
                    .contentTransition(.numericText())
            }
            .contentShape(Rectangle())
            .frame(minHeight: ExperienceAccessibility.minTouchTarget)
        }
        .buttonStyle(.experiencePlain)
        .disabled(action == nil)
        .accessibilityLabel("\(title), \(value). Double tap to view trades.")
    }
}

// MARK: - Sessions horizontal bars

struct DashboardSessionBarsView: View {
    var performance: [DashboardSessionPerformanceRow] = []
    var sessions: [ProfileStatisticsMetrics.SessionRow] = []
    var onSelect: ((String) -> Void)?

    @Environment(\.themeColors) private var colors

    private var rows: [DashboardSessionPerformanceRow] {
        if !performance.isEmpty { return performance }
        return sessions.map {
            DashboardSessionPerformanceRow(
                label: $0.label,
                tradeCount: $0.count,
                netPnL: 0,
                wins: 0,
                losses: 0,
                winRate: nil
            )
        }
    }

    var body: some View {
        if rows.isEmpty {
            DashboardChartEmptyCopy(
                message: "Tag sessions on trades to unlock your session breakdown."
            )
        } else {
            let maxAbs = max(rows.map { abs($0.netPnL) }.max() ?? 0, 1)
            ProposedWidthClamp {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                ForEach(rows) { row in
                    Button {
                        onSelect?(row.label)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(sessionTitle(row.label))
                                    .experienceStyle(.caption, color: colors.secondaryText)
                                Spacer(minLength: 8)
                                Text(signedMoney(row.netPnL))
                                    .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                                    .foregroundStyle(toneColor(row.netPnL))
                                Text("· \(row.tradeCount)")
                                    .experienceStyle(.caption2, color: colors.tertiaryText)
                            }
                            GeometryReader { geo in
                                let width = row.netPnL == 0
                                    ? 0
                                    : max(8, geo.size.width * CGFloat(abs(row.netPnL) / maxAbs))
                                HStack(spacing: 0) {
                                    if row.netPnL < 0 {
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
                            if let winRate = row.winRate {
                                Text("\(Int(winRate.rounded()))% win rate")
                                    .experienceStyle(.caption2, color: colors.tertiaryText)
                            }
                        }
                        .contentShape(Rectangle())
                        .frame(minHeight: ExperienceAccessibility.minTouchTarget)
                    }
                    .buttonStyle(.experiencePlain)
                    .accessibilityLabel("\(row.label), \(signedMoney(row.netPnL)), \(row.tradeCount) trades.")
                }
            }
            }
        }
    }

    private func sessionTitle(_ label: String) -> String {
        TradingSessionCatalog.displayTitle(for: label)
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

// MARK: - Weekday heatmap

struct DashboardWeekdayHeatmapView: View {
    let points: [DashboardBarPoint]
    var onSelect: ((String) -> Void)?

    @Environment(\.themeColors) private var colors

    private var maxAbs: Double {
        max(points.map { abs($0.value) }.max() ?? 0, 1)
    }

    private var hasActivity: Bool {
        points.contains { abs($0.value) > 0.01 }
    }

    private var bestLabel: String? {
        points.max(by: { $0.value < $1.value }).flatMap { $0.value > 0.01 ? $0.label : nil }
    }

    private var worstLabel: String? {
        points.min(by: { $0.value < $1.value }).flatMap { $0.value < -0.01 ? $0.label : nil }
    }

    var body: some View {
        if !hasActivity {
            DashboardChartEmptyCopy(
                message: "Complete a few more trades to unlock your weekday heatmap."
            )
        } else {
            ProposedWidthClamp {
                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    if bestLabel != nil || worstLabel != nil {
                        HStack(spacing: ExperienceSpacing.md) {
                            bestWorstLabels
                        }
                    }
                    HStack(spacing: ExperienceSpacing.xs) {
                        ForEach(points) { point in
                            Button {
                                onSelect?(point.label)
                            } label: {
                                VStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                                        .fill(cellColor(point.value))
                                        .overlay {
                                            if point.label == bestLabel || point.label == worstLabel {
                                                RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                                                    .stroke(colors.primaryText.opacity(0.45), lineWidth: 1)
                                            }
                                        }
                                        .frame(height: 44)
                                        .overlay {
                                            if abs(point.value) < 0.01 {
                                                Text("·")
                                                    .experienceStyle(.caption2, color: colors.tertiaryText)
                                            } else {
                                                Text(point.value >= 0 ? "+" : "−")
                                                    .font(.system(.caption2, design: .rounded).weight(.bold))
                                                    .foregroundStyle(colors.primaryText.opacity(0.85))
                                            }
                                        }
                                    Text(point.label)
                                        .experienceStyle(.caption2, color: colors.tertiaryText)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.experiencePlain)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("\(point.label), \(moneyLabel(point.value)). Double tap to view trades.")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bestWorstLabels: some View {
        if let best = bestLabel, let p = points.first(where: { $0.label == best }) {
            Text("Best \(best) · \(moneyLabel(p.value))")
                .experienceStyle(.caption2, color: colors.profit)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        if let worst = worstLabel, let p = points.first(where: { $0.label == worst }) {
            Text("Worst \(worst) · \(moneyLabel(p.value))")
                .experienceStyle(.caption2, color: colors.loss)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func cellColor(_ value: Double) -> Color {
        let intensity = min(abs(value) / maxAbs, 1)
        if abs(value) < 0.01 {
            return colors.fillSecondary.opacity(0.55)
        }
        let base = value >= 0 ? colors.profit : colors.loss
        return base.opacity(0.25 + intensity * 0.65)
    }

    private func moneyLabel(_ value: Double) -> String {
        NumberDisplay.chartCurrency(value)
    }
}

// MARK: - Trading hours (24h activity timeline)

/// Fitness-style 24-hour activity band — same ``hourHeatmap`` P&L data as before.
///
/// Height encodes intensity; color encodes profit vs loss. Taps still open the journal.
struct DashboardHourTimelineView: View {
    let points: [DashboardBarPoint]
    var highlights: DashboardHourHighlights?
    var onSelect: ((String) -> Void)?

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedLabel: String?

    private let plotHeight: CGFloat = 88

    private var maxAbs: Double {
        max(points.map { abs($0.value) }.max() ?? 0, 1)
    }

    private var selectedPoint: DashboardBarPoint? {
        guard let selectedLabel else { return nil }
        return points.first { $0.label == selectedLabel }
    }

    private var bestHourLabel: String? {
        if let hour = highlights?.bestHour { return String(format: "%02d", hour) }
        return points.max(by: { $0.value < $1.value }).flatMap { abs($0.value) > 0.01 ? $0.label : nil }
    }

    private var worstHourLabel: String? {
        if let hour = highlights?.worstHour { return String(format: "%02d", hour) }
        return points.min(by: { $0.value < $1.value }).flatMap { abs($0.value) > 0.01 ? $0.label : nil }
    }

    var body: some View {
        ProposedWidthClamp {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            headerSummary
            if bestHourLabel != nil || worstHourLabel != nil {
                HStack(spacing: ExperienceSpacing.md) {
                    if let best = bestHourLabel {
                        highlightChip(title: "Best", label: best, value: highlights?.bestPnL ?? points.first { $0.label == best }?.value)
                    }
                    if let worst = worstHourLabel, worst != bestHourLabel {
                        highlightChip(title: "Worst", label: worst, value: highlights?.worstPnL ?? points.first { $0.label == worst }?.value)
                    }
                    Spacer(minLength: 0)
                }
            }

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(points) { point in
                    Button {
                        selectedLabel = point.label
                        onSelect?(point.label)
                    } label: {
                        hourBar(for: point)
                    }
                    .buttonStyle(.experiencePlain)
                    .accessibilityLabel(
                        "Hour \(point.label), \(moneyLabel(point.value)). Double tap to view trades."
                    )
                    .accessibilityAddTraits(selectedLabel == point.label ? .isSelected : [])
                }
            }
            .frame(height: plotHeight)
            .padding(.top, ExperienceSpacing.xs)

            axisLabels
        }
        }
    }

    private var headerSummary: some View {
        HStack(alignment: .firstTextBaseline) {
            if let selected = selectedPoint {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hourDisplay(selected.label))
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                    Text(signedMoney(selected.value))
                        .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(toneColor(selected.value))
                        .contentTransition(.numericText())
                }
            } else if let label = bestHourLabel {
                let value = highlights?.bestPnL ?? points.first { $0.label == label }?.value ?? 0
                VStack(alignment: .leading, spacing: 2) {
                    Text("Peak hour")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                    Text("\(hourDisplay(label)) · \(signedMoney(value))")
                        .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(toneColor(value))
                        .contentTransition(.numericText())
                }
            } else {
                Text("Across the day")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            }
            Spacer(minLength: 0)
        }
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
            value: selectedLabel
        )
    }

    private var axisLabels: some View {
        HStack {
            Text("12a")
                .experienceStyle(.caption2, color: colors.tertiaryText)
            Spacer()
            Text("6a")
                .experienceStyle(.caption2, color: colors.tertiaryText)
            Spacer()
            Text("12p")
                .experienceStyle(.caption2, color: colors.tertiaryText)
            Spacer()
            Text("6p")
                .experienceStyle(.caption2, color: colors.tertiaryText)
            Spacer()
            Text("12a")
                .experienceStyle(.caption2, color: colors.tertiaryText)
        }
    }

    private func hourBar(for point: DashboardBarPoint) -> some View {
        let intensity = abs(point.value) / maxAbs
        let hasActivity = abs(point.value) > 0.01
        let barHeight = hasActivity
            ? max(plotHeight * 0.14, plotHeight * intensity)
            : 3
        let isSelected = selectedLabel == point.label

        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(barColor(value: point.value, intensity: intensity, hasActivity: hasActivity))
                .frame(maxWidth: .infinity)
                .frame(height: barHeight)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .stroke(colors.primaryText.opacity(0.55), lineWidth: 1)
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .contentShape(Rectangle())
    }

    private func barColor(value: Double, intensity: Double, hasActivity: Bool) -> Color {
        guard hasActivity else {
            return colors.fillSecondary.opacity(0.55)
        }
        let base = value >= 0 ? colors.profit : colors.loss
        return base.opacity(0.35 + intensity * 0.55)
    }

    private func toneColor(_ value: Double) -> Color {
        if value > 0.01 { return colors.profit }
        if value < -0.01 { return colors.loss }
        return colors.secondaryText
    }

    private func hourDisplay(_ label: String) -> String {
        guard let hour = Int(label) else { return label }
        switch hour {
        case 0: return "12 AM"
        case 12: return "12 PM"
        case 1..<12: return "\(hour) AM"
        default: return "\(hour - 12) PM"
        }
    }

    private func signedMoney(_ value: Double) -> String {
        NumberDisplay.chartSignedCurrency(value)
    }

    private func moneyLabel(_ value: Double) -> String {
        NumberDisplay.chartCurrency(value)
    }

    private func highlightChip(title: String, label: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .experienceStyle(.caption2, color: colors.tertiaryText)
            Text("\(hourDisplay(label)) · \(signedMoney(value ?? 0))")
                .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(toneColor(value ?? 0))
        }
    }
}

/// Legacy alias — call sites may still reference the heatmap name.
typealias DashboardHourHeatmapView = DashboardHourTimelineView

// MARK: - Long / Short donut

struct DashboardLongShortDonutView: View {
    let longCount: Int
    let shortCount: Int
    let longPnL: Double
    let shortPnL: Double
    var onSelectLong: (() -> Void)?
    var onSelectShort: (() -> Void)?

    @Environment(\.themeColors) private var colors

    private var total: Int { longCount + shortCount }

    var body: some View {
        if total == 0 {
            DashboardChartEmptyCopy(
                message: "Log long and short trades to compare your directional mix."
            )
        } else {
            HStack(spacing: ExperienceSpacing.lg) {
                ZStack {
                    Chart {
                        SectorMark(
                            angle: .value("Long", max(longCount, 0)),
                            innerRadius: .ratio(0.58),
                            angularInset: 1.5
                        )
                        .foregroundStyle(colors.accent)
                        .cornerRadius(3)

                        SectorMark(
                            angle: .value("Short", max(shortCount, 0)),
                            innerRadius: .ratio(0.58),
                            angularInset: 1.5
                        )
                        .foregroundStyle(colors.secondaryText.opacity(0.55))
                        .cornerRadius(3)
                    }
                    .frame(width: 120, height: 120)
                    .accessibilityHidden(true)

                    VStack(spacing: 2) {
                        Text(NumberDisplay.integer(total))
                            .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                            .foregroundStyle(colors.primaryText)
                            .contentTransition(.numericText())
                        Text("trades")
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                    }
                }

                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    sideButton(
                        title: "Long",
                        count: longCount,
                        pnl: longPnL,
                        swatch: colors.accent,
                        action: onSelectLong
                    )
                    sideButton(
                        title: "Short",
                        count: shortCount,
                        pnl: shortPnL,
                        swatch: colors.secondaryText.opacity(0.55),
                        action: onSelectShort
                    )
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func sideButton(
        title: String,
        count: Int,
        pnl: Double,
        swatch: Color,
        action: (() -> Void)?
    ) -> some View {
        Button {
            action?()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(swatch).frame(width: 8, height: 8)
                    Text(title)
                        .experienceStyle(.callout, color: colors.primaryText)
                    Text("· \(NumberDisplay.integer(count))")
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .contentTransition(.numericText())
                }
                Text(signedMoney(pnl))
                    .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(pnl >= 0 ? colors.profit : colors.loss)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .frame(minHeight: ExperienceAccessibility.minTouchTarget)
        }
        .buttonStyle(.experiencePlain)
        .disabled(action == nil)
        .accessibilityLabel("\(title), \(count) trades. Double tap to view trades.")
    }

    private func signedMoney(_ value: Double) -> String {
        NumberDisplay.chartSignedCurrency(value)
    }
}

// MARK: - Hold time histogram

private struct HoldHistogramChartPoint: Identifiable {
    var id: Int { index }
    var index: Int
    var label: String
    var count: Int
    var averageNetPnL: Double
}

private struct HoldHistogramYScale {
    var axisMax: Int
    var ticks: [Int]

    static func nice(peak: Int) -> HoldHistogramYScale {
        guard peak > 0 else { return HoldHistogramYScale(axisMax: 1, ticks: [0, 1]) }
        let divisions = 4
        let rawStep = Double(peak) / Double(divisions)
        let magnitude = pow(10.0, floor(log10(max(rawStep, 1))))
        let residual = rawStep / magnitude
        let niceResidual: Double
        if residual <= 1 { niceResidual = 1 }
        else if residual <= 2 { niceResidual = 2 }
        else if residual <= 5 { niceResidual = 5 }
        else { niceResidual = 10 }
        let step = max(1, Int((niceResidual * magnitude).rounded()))
        var niceMax = step * divisions
        while niceMax < peak { niceMax += step }
        let ticks = stride(from: 0, through: niceMax, by: step).map(\.self)
        return HoldHistogramYScale(axisMax: niceMax, ticks: ticks)
    }
}

private struct HoldHistogramPnLYScale {
    /// Upper bound for bar height — max absolute average P&L in the plot.
    var axisMax: Double
    /// Magnitude ticks only ($0, $100, …); signed values stay in data and labels.
    var tickValues: [Double]

    static func resolve(averages: [Double]) -> HoldHistogramPnLYScale {
        let values = averages.filter(\.isFinite)
        let magnitudePeak = values.map { abs($0) }.max() ?? 0

        if magnitudePeak < 0.01 {
            return HoldHistogramPnLYScale(axisMax: 100, tickValues: [0, 50, 100])
        }

        let axisMax = niceLimit(max(magnitudePeak, 1))
        let ticks = [0, axisMax / 2, axisMax].uniqued().sorted()
        return HoldHistogramPnLYScale(axisMax: axisMax, tickValues: ticks)
    }

    private static func niceLimit(_ value: Double) -> Double {
        guard value > 0 else { return 0 }
        let magnitude = pow(10.0, floor(log10(value)))
        let residual = value / magnitude
        let factor: Double
        if residual <= 1 { factor = 1 }
        else if residual <= 2 { factor = 2 }
        else if residual <= 5 { factor = 5 }
        else { factor = 10 }
        var nice = factor * magnitude
        while nice < value { nice += factor * magnitude / 4 }
        return nice
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

/// Native SwiftUI grouped histogram (trade count + avg P&L per bucket).
private struct HoldHistogramManualChart<Tooltip: View>: View {
    let chartPoints: [HoldHistogramChartPoint]
    let buckets: [DashboardHistogramBucket]
    let tradeCountScale: HoldHistogramYScale
    let pnlScale: HoldHistogramPnLYScale
    let colors: SemanticColorPalette
    /// Persistent bucket index for accessibility adjustment only — not set by touch drag.
    @Binding var selectedIndex: Int?
    @GestureState private var inspectLocationX: CGFloat?
    let tradeBarFill: (HoldHistogramChartPoint) -> Color
    @ViewBuilder let tooltip: (DashboardHistogramBucket) -> Tooltip

    private let plotHeight: CGFloat = 132
    private let leadingAxisWidth: CGFloat = 26
    private let trailingAxisWidth: CGFloat = 38
    private let xAxisHeight: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            legend

            HStack(alignment: .top, spacing: 6) {
                tradeCountAxis
                plotArea
                    .frame(height: plotHeight)
                pnlAxis
            }

            xAxisLabels
                .padding(.leading, leadingAxisWidth + 6)
                .padding(.trailing, trailingAxisWidth + 6)
        }
    }

    private var legend: some View {
        HStack(spacing: ExperienceSpacing.md) {
            legendSwatch(colors.accent, title: "Trades")
            legendSwatch(nil, title: "Avg P&L", gradient: (colors.profit, colors.loss))
            Spacer(minLength: 0)
        }
    }

    private func legendSwatch(
        _ color: Color?,
        title: String,
        gradient: (Color, Color)? = nil
    ) -> some View {
        HStack(spacing: 5) {
            if let gradient {
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(gradient.0)
                        .frame(width: 6, height: 8)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(gradient.1)
                        .frame(width: 6, height: 8)
                }
            } else if let color {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(title)
                .experienceStyle(.caption2, color: colors.tertiaryText)
        }
    }

    private var tradeCountAxis: some View {
        GeometryReader { geo in
            ZStack(alignment: .trailing) {
                ForEach(tradeCountScale.ticks, id: \.self) { tick in
                    Text("\(tick)")
                        .font(.system(.caption2, design: .rounded).monospacedDigit())
                        .foregroundStyle(colors.tertiaryText)
                        .position(x: leadingAxisWidth - 2, y: tradeCountY(tick, height: geo.size.height))
                }
            }
        }
        .frame(width: leadingAxisWidth, height: plotHeight)
    }

    private var pnlAxis: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                ForEach(pnlScale.tickValues, id: \.self) { tick in
                    Text(formatPnlAxisTick(tick))
                        .font(.system(.caption2, design: .rounded).monospacedDigit())
                        .foregroundStyle(colors.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: trailingAxisWidth, alignment: .leading)
                        .position(x: trailingAxisWidth / 2, y: pnlMagnitudeY(tick, height: geo.size.height))
                }
            }
        }
        .frame(width: trailingAxisWidth, height: plotHeight)
    }

    private var xAxisLabels: some View {
        HStack(spacing: 0) {
            ForEach(chartPoints) { point in
                Text(point.label)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(colors.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: xAxisHeight)
    }

    private func highlightedIndex(plotWidth: CGFloat) -> Int? {
        if let inspectLocationX {
            return bucketIndex(at: inspectLocationX, plotWidth: plotWidth)
        }
        return selectedIndex
    }

    private var plotArea: some View {
        GeometryReader { geo in
            let slotWidth = geo.size.width / CGFloat(max(chartPoints.count, 1))
            let dualBarWidth = max(5, slotWidth * 0.24)
            let plotBounds = CGRect(origin: .zero, size: geo.size)
            let highlightIndex = highlightedIndex(plotWidth: geo.size.width)

            ZStack(alignment: .bottomLeading) {
                tradeCountGridLines(in: geo.size)
                pnlBaseline(in: geo.size)
                pnlGridLines(in: geo.size)

                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(chartPoints) { point in
                        HStack(alignment: .bottom, spacing: max(2, slotWidth * 0.06)) {
                            Group {
                                if point.count > 0 {
                                    barColumnShape
                                        .fill(tradeBarFill(point))
                                        .frame(
                                            width: dualBarWidth,
                                            height: tradeBarHeight(for: point.count, plotHeight: geo.size.height)
                                        )
                                } else {
                                    Color.clear.frame(width: dualBarWidth, height: 1)
                                }
                            }
                            .frame(width: dualBarWidth, alignment: .bottom)

                            pnlBar(
                                average: point.averageNetPnL,
                                barWidth: dualBarWidth,
                                plotHeight: geo.size.height
                            )
                        }
                        .frame(width: slotWidth, height: geo.size.height, alignment: .bottom)
                    }
                }

                if let highlightIndex, buckets.indices.contains(highlightIndex) {
                    selectionLayer(
                        index: highlightIndex,
                        plotSize: geo.size,
                        slotWidth: slotWidth
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($inspectLocationX) { value, state, _ in
                        if plotBounds.contains(value.location) {
                            state = value.location.x
                        } else {
                            state = nil
                        }
                    }
            )
        }
    }

    @ViewBuilder
    private func pnlBar(
        average: Double,
        barWidth: CGFloat,
        plotHeight: CGFloat
    ) -> some View {
        let magnitude = abs(average)
        let height = pnlBarHeight(forMagnitude: magnitude, plotHeight: plotHeight)
        let fill = average >= 0 ? colors.profit : colors.loss
        Group {
            if magnitude > 0.005, height >= 1 {
                pnlPositiveBarShape
                    .fill(fill)
                    .frame(width: barWidth, height: height)
            } else {
                Color.clear.frame(width: barWidth, height: 1)
            }
        }
        .frame(width: barWidth, alignment: .bottom)
    }

    @ViewBuilder
    private func selectionLayer(index: Int, plotSize: CGSize, slotWidth: CGFloat) -> some View {
        let anchorX = (CGFloat(index) + 0.5) * slotWidth
        let bucket = buckets[index]
        let columnWidth = max(28, slotWidth * 0.7)

        ZStack {
            Rectangle()
                .fill(colors.accent.opacity(0.18))
                .frame(width: columnWidth, height: plotSize.height)
                .position(x: anchorX, y: plotSize.height / 2)

            selectionRule(at: index, plotSize: plotSize, slotWidth: slotWidth)

            tooltip(bucket)
                .fixedSize()
                .position(
                    x: min(max(anchorX, 72), plotSize.width - 72),
                    y: -6
                )
        }
        .allowsHitTesting(false)
    }

    private func selectionRule(at index: Int, plotSize: CGSize, slotWidth: CGFloat) -> some View {
        let x = (CGFloat(index) + 0.5) * slotWidth
        return Rectangle()
            .fill(colors.accent.opacity(0.55))
            .frame(width: 1.2, height: plotSize.height)
            .position(x: x, y: plotSize.height / 2)
    }

    private func tradeCountGridLines(in size: CGSize) -> some View {
        ZStack {
            ForEach(tradeCountScale.ticks.filter { $0 > 0 }, id: \.self) { tick in
                Path { path in
                    let y = tradeCountY(tick, height: size.height)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                .stroke(colors.border.opacity(0.35), lineWidth: 0.5)
            }
        }
    }

    private func pnlGridLines(in size: CGSize) -> some View {
        ZStack {
            ForEach(pnlScale.tickValues.filter { $0 > 0.01 }, id: \.self) { tick in
                Path { path in
                    let y = pnlMagnitudeY(tick, height: size.height)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                .stroke(colors.border.opacity(0.22), lineWidth: 0.5)
            }
        }
    }

    private func pnlBaseline(in size: CGSize) -> some View {
        Path { path in
            let y = size.height
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        .stroke(colors.border.opacity(0.55), lineWidth: 0.75)
    }

    private func tradeBarHeight(for count: Int, plotHeight: CGFloat) -> CGFloat {
        guard count > 0, tradeCountScale.axisMax > 0 else { return 0 }
        return max(2, plotHeight * CGFloat(count) / CGFloat(tradeCountScale.axisMax))
    }

    private func tradeCountY(_ tick: Int, height: CGFloat) -> CGFloat {
        guard tradeCountScale.axisMax > 0 else { return height }
        return height * (1 - CGFloat(tick) / CGFloat(tradeCountScale.axisMax))
    }

    private func pnlBarHeight(forMagnitude magnitude: Double, plotHeight: CGFloat) -> CGFloat {
        guard magnitude > 0, pnlScale.axisMax > 0 else { return 0 }
        return max(2, plotHeight * CGFloat(magnitude / pnlScale.axisMax))
    }

    private func pnlMagnitudeY(_ tick: Double, height: CGFloat) -> CGFloat {
        guard pnlScale.axisMax > 0 else { return height }
        return height * (1 - CGFloat(tick / pnlScale.axisMax))
    }

    private func formatPnlAxisTick(_ value: Double) -> String {
        if value < 0.5 { return "$0" }
        return NumberDisplay.compactCurrencyAxis(Decimal(value))
    }

    private func bucketIndex(at x: CGFloat, plotWidth: CGFloat) -> Int {
        guard !chartPoints.isEmpty, plotWidth > 0 else { return 0 }
        let slotWidth = plotWidth / CGFloat(chartPoints.count)
        let raw = Int((x / slotWidth).rounded(.down))
        return min(max(raw, 0), chartPoints.count - 1)
    }

    private var barColumnShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 4,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 4,
            style: .continuous
        )
    }

    private var pnlPositiveBarShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 4,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 4,
            style: .continuous
        )
    }

}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

struct DashboardHoldHistogramView: View {
    let buckets: [DashboardHistogramBucket]
    let averages: [DashboardHoldTimeRow]
    var holdExtremes: [DashboardHoldExtremeSnapshot] = []
    var onSelectBucket: ((String) -> Void)?

    @Environment(\.themeColors) private var colors
    @State private var selectedIndex: Int?

    private var chartPoints: [HoldHistogramChartPoint] {
        buckets.enumerated().map { offset, bucket in
            HoldHistogramChartPoint(
                index: offset,
                label: bucket.label,
                count: bucket.count,
                averageNetPnL: bucket.averageNetPnL
            )
        }
    }

    private var totalTrades: Int {
        buckets.reduce(0) { $0 + $1.count }
    }

    private var tradeCountScale: HoldHistogramYScale {
        HoldHistogramYScale.nice(peak: buckets.map(\.count).max() ?? 0)
    }

    private var pnlScale: HoldHistogramPnLYScale {
        HoldHistogramPnLYScale.resolve(averages: buckets.map(\.averageNetPnL))
    }

    var body: some View {
        if buckets.allSatisfy({ $0.count == 0 }) {
            DashboardChartEmptyCopy(
                message: "Your hold time distribution will appear after more completed trades."
            )
        } else {
            ProposedWidthClamp {
                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    holdHistogramChart
                        .accessibilityLabel("Hold time distribution")

                    if !averages.isEmpty {
                        HStack(spacing: 0) {
                            ForEach(Array(averages.enumerated()), id: \.element.id) { index, row in
                                VStack(spacing: 2) {
                                    Text(row.label)
                                        .experienceStyle(.caption2, color: colors.tertiaryText)
                                    Text(row.value)
                                        .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                                        .foregroundStyle(colors.primaryText)
                                        .contentTransition(.numericText())
                                }
                                .frame(maxWidth: .infinity)
                                if index < averages.count - 1 {
                                    Rectangle()
                                        .fill(colors.border.opacity(0.45))
                                        .frame(width: ExperienceBorder.hairline, height: 24)
                                }
                            }
                        }
                    }

                    if !holdExtremes.isEmpty {
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            alignment: .center,
                            spacing: ExperienceSpacing.xs
                        ) {
                            ForEach(holdExtremes, id: \.label) { row in
                                VStack(alignment: .center, spacing: 2) {
                                    Text(row.label)
                                        .experienceStyle(.caption2, color: colors.tertiaryText)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.85)
                                    Text(formatDuration(row.durationSeconds))
                                        .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                                        .foregroundStyle(colors.primaryText)
                                    Text(signedMoney(row.pnl))
                                        .font(.system(.caption2, design: .rounded).weight(.medium).monospacedDigit())
                                        .foregroundStyle(row.pnl >= 0 ? colors.profit : colors.loss)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
        }
    }

    private var holdHistogramChart: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            holdChart

            if let index = selectedIndex,
               let bucket = buckets[safe: index],
               bucket.count > 0,
               let onSelectBucket
            {
                Button {
                    ExperienceHaptics.play(.selection)
                    onSelectBucket(bucket.label)
                } label: {
                    Text("View \(bucket.label) trades")
                        .experienceStyle(.caption2, color: colors.accent)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.experiencePlain)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(ExperienceSpacing.sm)
        .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(
            cornerRadius: ExperienceRadius.md,
            style: .continuous
        ))
        .onChange(of: selectedIndex) { _, newValue in
            guard newValue != nil else { return }
            ExperienceHaptics.play(.selection)
        }
    }

    private var holdChart: some View {
        HoldHistogramManualChart(
            chartPoints: chartPoints,
            buckets: buckets,
            tradeCountScale: tradeCountScale,
            pnlScale: pnlScale,
            colors: colors,
            selectedIndex: $selectedIndex,
            tradeBarFill: tradeBarFill(for:),
            tooltip: holdTooltip(for:)
        )
        .accessibilityHint("Press and drag horizontally to inspect each hold-time range.")
        .accessibilityAdjustableAction { direction in
            guard !buckets.isEmpty else { return }
            let current = selectedIndex ?? 0
            switch direction {
            case .increment:
                selectedIndex = min(current + 1, buckets.count - 1)
            case .decrement:
                selectedIndex = max(current - 1, 0)
            @unknown default:
                break
            }
        }
    }

    private func holdTooltip(for bucket: DashboardHistogramBucket) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(bucket.label)
                .experienceStyle(.caption, color: colors.primaryText)
                .fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(bucket.count) trades · \(holdPercentLabel(bucket.count))")
                    .experienceStyle(.caption2, color: colors.secondaryText)
                Text("Avg \(signedMoney(bucket.averageNetPnL))")
                    .font(.system(.caption2, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(bucket.averageNetPnL >= 0 ? colors.profit : colors.loss)
            }
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .padding(.vertical, ExperienceSpacing.xs)
        .background(colors.fillPrimary.opacity(0.92), in: RoundedRectangle(
            cornerRadius: ExperienceRadius.sm,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                .stroke(colors.accent.opacity(0.35), lineWidth: ExperienceBorder.hairline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tradeBarFill(for point: HoldHistogramChartPoint) -> Color {
        if point.count == 0 {
            return colors.accent.opacity(0.28)
        }
        return colors.accent
    }

    private func holdPercentLabel(_ count: Int) -> String {
        guard totalTrades > 0 else { return "0%" }
        let pct = (Double(count) / Double(totalTrades)) * 100
        return NumberDisplay.percent(
            pct,
            minimumFractionDigits: 0,
            maximumFractionDigits: count == totalTrades ? 0 : 1
        )
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(total)s"
    }

    private func signedMoney(_ value: Double) -> String {
        NumberDisplay.chartSignedCurrency(value)
    }
}

// MARK: - Expanded analytics visuals

struct DashboardSymbolRankedBarsView: View {
    let rows: [DashboardSymbolPerformanceRow]

    @Environment(\.themeColors) private var colors

    var body: some View {
        if rows.isEmpty {
            DashboardChartEmptyCopy(message: "Symbol performance appears after you log a few tickers.")
        } else {
            let maxAbs = max(rows.map { abs($0.netPnL) }.max() ?? 0, 1)
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                ForEach(rows.prefix(8)) { row in
                    HStack(spacing: ExperienceSpacing.sm) {
                        Text(row.ticker)
                            .font(.system(.callout, design: .rounded).weight(.semibold).monospaced())
                            .foregroundStyle(colors.primaryText)
                            .frame(width: 52, alignment: .leading)
                        GeometryReader { geo in
                            let width = max(6, geo.size.width * CGFloat(abs(row.netPnL) / maxAbs))
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(row.netPnL >= 0 ? colors.profit.opacity(0.85) : colors.loss.opacity(0.85))
                                .frame(width: width, height: 12)
                                .frame(maxWidth: .infinity, alignment: row.netPnL >= 0 ? .leading : .trailing)
                        }
                        .frame(height: 12)
                        Text(signedMoney(row.netPnL))
                            .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(row.netPnL >= 0 ? colors.profit : colors.loss)
                            .frame(width: 72, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.ticker), \(signedMoney(row.netPnL)), \(row.trades) trades")
                }
            }
        }
    }

    private func signedMoney(_ value: Double) -> String {
        NumberDisplay.chartSignedCurrency(value)
    }
}

struct DashboardLongShortComparisonView: View {
    let comparison: DashboardLongShortComparison
    var onSelectLong: (() -> Void)?
    var onSelectShort: (() -> Void)?

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.md) {
            sideColumn(title: "Long", side: comparison.long, swatch: colors.profit, action: onSelectLong)
            sideColumn(title: "Short", side: comparison.short, swatch: colors.accent, action: onSelectShort)
        }
    }

    private func sideColumn(
        title: String,
        side: DashboardDirectionSideSnapshot?,
        swatch: Color,
        action: (() -> Void)?
    ) -> some View {
        Button {
            action?()
        } label: {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                HStack(spacing: 6) {
                    Circle().fill(swatch).frame(width: 8, height: 8)
                    Text(title)
                        .experienceStyle(.subheadline, color: colors.primaryText)
                        .fontWeight(.semibold)
                }
                if let side {
                    Text(signedMoney(side.netPnL))
                        .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(side.netPnL >= 0 ? colors.profit : colors.loss)
                    performanceBar(side: side)
                    Text("\(Int((side.winRate ?? 0).rounded()))% WR · \(side.trades) trades")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                } else {
                    Text("No trades")
                        .experienceStyle(.caption, color: colors.tertiaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.experiencePlain)
        .disabled(action == nil || side == nil)
    }

    private func performanceBar(side: DashboardDirectionSideSnapshot) -> some View {
        let magnitude = abs(side.netPnL)
        let maxSide = max(abs(comparison.long?.netPnL ?? 0), abs(comparison.short?.netPnL ?? 0), 1)
        return GeometryReader { geo in
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(side.netPnL >= 0 ? colors.profit.opacity(0.8) : colors.loss.opacity(0.8))
                .frame(width: max(8, geo.size.width * CGFloat(magnitude / maxSide)), height: 10)
        }
        .frame(height: 10)
    }

    private func signedMoney(_ value: Double) -> String {
        NumberDisplay.chartSignedCurrency(value)
    }
}

struct DashboardStrategyHighlightsView: View {
    let highlights: DashboardStrategyHighlights

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            if let best = highlights.best {
                strategyRow(title: "Strongest setup", highlight: best, tone: colors.profit)
            }
            if let worst = highlights.worst, worst.netPnL < 0 {
                strategyRow(title: "Weakest setup", highlight: worst, tone: colors.loss)
            }
        }
    }

    private func strategyRow(title: String, highlight: DashboardStrategyHighlight, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .experienceStyle(.callout, color: colors.primaryText)
                .fontWeight(.bold)
            Text(highlight.strategy)
                .experienceStyle(.subheadline, color: colors.tertiaryText)
                .fontWeight(.semibold)
            HStack(spacing: ExperienceSpacing.sm) {
                Text(NumberDisplay.chartSignedCurrency(highlight.netPnL))
                    .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(tone)
                Text("· \(highlight.trades) trades")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                if let wr = highlight.winRate {
                    Text("· \(Int(wr.rounded()))% WR")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Underwater drawdown

struct DashboardUnderwaterDrawdownView: View {
    let series: [DashboardDrawdownPoint]
    let maxDrawdown: Decimal

    @Environment(\.themeColors) private var colors
    @State private var selectedIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Max drawdown")
                        .experienceStyle(.caption2, color: colors.secondaryText)
                    Text(DashboardViewModel.money(maxDrawdown))
                        .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(maxDrawdown > 0 ? colors.loss : colors.primaryText)
                        .contentTransition(.numericText())
                }
                Spacer()
                if let selected = selectedPoint {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Trade \(selected.index + 1)")
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                        Text(axisMoney(selected.depth))
                            .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(colors.loss)
                            .contentTransition(.numericText())
                    }
                }
            }

            if series.count >= 2 {
                Chart(series) { point in
                    AreaMark(
                        x: .value("Trade", point.index),
                        y: .value("Drawdown", point.depth)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(colors.loss.opacity(0.35))

                    LineMark(
                        x: .value("Trade", point.index),
                        y: .value("Drawdown", point.depth)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .foregroundStyle(colors.loss)

                    if let selectedIndex, point.index == selectedIndex {
                        RuleMark(x: .value("Selected", selectedIndex))
                            .foregroundStyle(colors.tertiaryText.opacity(0.55))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        PointMark(
                            x: .value("Selected", selectedIndex),
                            y: .value("Drawdown", point.depth)
                        )
                        .symbolSize(48)
                        .foregroundStyle(colors.loss)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: true))
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(colors.border.opacity(0.35))
                        AxisValueLabel {
                            if let raw = value.as(Double.self) {
                                Text(axisMoney(raw))
                                    .font(.system(.caption2, design: .rounded).monospacedDigit())
                                    .foregroundStyle(colors.tertiaryText)
                            }
                        }
                    }
                }
                .chartXSelection(value: $selectedIndex)
                .frame(height: 140)
                .accessibilityLabel(
                    "Underwater drawdown chart. Maximum drawdown \(DashboardViewModel.money(maxDrawdown))."
                )
                .accessibilityHint("Adjustable. Scrub horizontally to inspect drawdown at each trade.")
            } else {
                DashboardChartEmptyCopy(
                    message: "Add more trades to visualize how deep equity dips from peaks."
                )
            }
        }
        .padding(ExperienceSpacing.md)
        .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(
            cornerRadius: ExperienceRadius.md,
            style: .continuous
        ))
    }

    private var selectedPoint: DashboardDrawdownPoint? {
        guard let selectedIndex else { return nil }
        return series.first { $0.index == selectedIndex }
    }

    private func axisMoney(_ value: Double) -> String {
        NumberDisplay.chartCurrency(value)
    }
}

// MARK: - Empty copy

struct DashboardChartEmptyCopy: View {
    let message: String

    @Environment(\.themeColors) private var colors

    var body: some View {
        Text(message)
            .experienceStyle(.footnote, color: colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, ExperienceSpacing.xs)
    }
}
