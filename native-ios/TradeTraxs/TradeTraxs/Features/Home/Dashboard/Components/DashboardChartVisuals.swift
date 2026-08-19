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
                            Text(String(format: "%.0f%%", winRate * 100))
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
                            value: "\(winCount)",
                            color: colors.profit,
                            action: onSelectWins
                        )
                        legendButton(
                            symbol: "L",
                            title: "Losses",
                            value: "\(lossCount)",
                            color: colors.loss,
                            action: onSelectLosses
                        )
                        Text("\(total) closed outcomes")
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
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityLabel("\(title), \(value). Double tap to view trades.")
    }
}

// MARK: - Sessions horizontal bars

struct DashboardSessionBarsView: View {
    let sessions: [ProfileStatisticsMetrics.SessionRow]
    var onSelect: ((String) -> Void)?

    @Environment(\.themeColors) private var colors

    var body: some View {
        if sessions.isEmpty {
            DashboardChartEmptyCopy(
                message: "Tag sessions on trades to unlock your session breakdown."
            )
        } else {
            let maxCount = max(sessions.map(\.count).max() ?? 1, 1)
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                ForEach(sessions) { row in
                    Button {
                        onSelect?(row.label)
                    } label: {
                        HStack(spacing: ExperienceSpacing.sm) {
                            Text(row.label)
                                .experienceStyle(.caption, color: colors.secondaryText)
                                .frame(width: 72, alignment: .leading)
                                .lineLimit(1)
                            GeometryReader { geo in
                                let width = geo.size.width * CGFloat(row.count) / CGFloat(maxCount)
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(colors.accent.opacity(0.85))
                                    .frame(width: max(width, row.count > 0 ? 6 : 0), height: 14)
                                    .accessibilityHidden(true)
                            }
                            .frame(height: 14)
                            Text("\(row.count)")
                                .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                                .foregroundStyle(colors.primaryText)
                                .frame(width: 28, alignment: .trailing)
                                .contentTransition(.numericText())
                        }
                        .contentShape(Rectangle())
                        .frame(minHeight: ExperienceAccessibility.minTouchTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(row.label), \(row.count) trades. Double tap to view trades.")
                }
            }
        }
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

    var body: some View {
        if !hasActivity {
            DashboardChartEmptyCopy(
                message: "Complete a few more trades to unlock your weekday heatmap."
            )
        } else {
            HStack(spacing: ExperienceSpacing.xs) {
                ForEach(points) { point in
                    Button {
                        onSelect?(point.label)
                    } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                                .fill(cellColor(point.value))
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
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(point.label), \(moneyLabel(point.value)). Double tap to view trades.")
                }
            }
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
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Trading hours (24h activity timeline)

/// Fitness-style 24-hour activity band — same ``hourHeatmap`` P&L data as before.
///
/// Height encodes intensity; color encodes profit vs loss. Taps still open the journal.
struct DashboardHourTimelineView: View {
    let points: [DashboardBarPoint]
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

    private var bestHour: DashboardBarPoint? {
        points.max(by: { $0.value < $1.value }).flatMap { abs($0.value) > 0.01 ? $0 : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            headerSummary

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(points) { point in
                    Button {
                        selectedLabel = point.label
                        onSelect?(point.label)
                    } label: {
                        hourBar(for: point)
                    }
                    .buttonStyle(.plain)
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
            } else if let best = bestHour {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Peak hour")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                    Text("\(hourDisplay(best.label)) · \(signedMoney(best.value))")
                        .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(toneColor(best.value))
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
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        let absText = formatter.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
        if value > 0.01 { return "+\(absText)" }
        if value < -0.01 { return "−\(absText)" }
        return absText
    }

    private func moneyLabel(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
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
                        Text("\(total)")
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
                    Text("· \(count)")
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
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityLabel("\(title), \(count) trades. Double tap to view trades.")
    }

    private func signedMoney(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        let absStr = formatter.string(from: NSNumber(value: abs(value))) ?? "$0"
        if value > 0 { return "+\(absStr)" }
        if value < 0 { return "−\(absStr)" }
        return absStr
    }
}

// MARK: - Hold time histogram

struct DashboardHoldHistogramView: View {
    let buckets: [DashboardHistogramBucket]
    let averages: [DashboardHoldTimeRow]
    var onSelectBucket: ((String) -> Void)?

    @Environment(\.themeColors) private var colors

    var body: some View {
        if buckets.allSatisfy({ $0.count == 0 }) {
            DashboardChartEmptyCopy(
                message: "Your hold time distribution will appear after more completed trades."
            )
        } else {
            VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("Bucket", bucket.label),
                        y: .value("Trades", bucket.count)
                    )
                    .foregroundStyle(colors.accent.opacity(0.85))
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(colors.tertiaryText)
                            }
                        }
                    }
                }
                .frame(height: 120)
                .accessibilityLabel("Hold time distribution")

                // Discrete taps — avoid scrub-driven navigation.
                HStack(spacing: ExperienceSpacing.xs) {
                    ForEach(buckets.filter { $0.count > 0 }) { bucket in
                        Button {
                            ExperienceHaptics.play(.selection)
                            onSelectBucket?(bucket.label)
                        } label: {
                            Text("\(bucket.label) · \(bucket.count)")
                                .experienceStyle(.caption2, color: colors.primaryText)
                                .padding(.horizontal, ExperienceSpacing.sm)
                                .padding(.vertical, ExperienceSpacing.xs)
                                .background(colors.fillSecondary.opacity(0.55), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(bucket.label), \(bucket.count) trades. Double tap to view.")
                    }
                }

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
                                    .frame(width: ExperienceBorder.hairline, height: 28)
                            }
                        }
                    }
                    .padding(.vertical, ExperienceSpacing.xs)
                }
            }
        }
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
                } else {
                    Text("Drag to inspect")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
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
                    "Underwater drawdown chart. Maximum drawdown \(DashboardViewModel.money(maxDrawdown)). Drag to inspect depth."
                )
                .accessibilityHint("Adjustable. Drag to inspect drawdown at each trade.")
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
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
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
