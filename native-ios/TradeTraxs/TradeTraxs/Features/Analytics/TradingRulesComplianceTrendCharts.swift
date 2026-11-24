import SwiftUI
import Charts

struct TradingRulesComplianceTrendCharts: View {
    enum Layout {
        case standard
        case compact
    }

    let weekly: [TradingRulesComplianceAnalytics.TrendPoint]
    let monthly: [TradingRulesComplianceAnalytics.TrendPoint]
    var layout: Layout = .standard

    @Environment(\.themeColors) private var colors
    @State private var selectedWeeklyKey: String?
    @State private var selectedMonthlyKey: String?

    private var chartFrameHeight: CGFloat {
        layout == .compact ? 128 : 144
    }

    private enum YAxisLayout {
        /// Fixed column for 0% / 50% / 100% labels (right-aligned inside).
        static let labelColumnWidth: CGFloat = 38
        /// Gap between label column and plot (gridlines / bars).
        static let plotLeadingGap: CGFloat = 10
    }

    var body: some View {
        VStack(alignment: .leading, spacing: layout == .compact ? ExperienceSpacing.sm : ExperienceSpacing.md) {
            trendBlock(
                title: "Weekly",
                points: weekly.suffix(8),
                period: .weekly,
                selectedPeriodKey: $selectedWeeklyKey
            )
            trendBlock(
                title: "Monthly",
                points: monthly.suffix(8),
                period: .monthly,
                selectedPeriodKey: $selectedMonthlyKey
            )
        }
    }

    @ViewBuilder
    private func trendBlock(
        title: String,
        points: ArraySlice<TradingRulesComplianceAnalytics.TrendPoint>,
        period: TradingRulesComplianceTrendAxisFormat.Period,
        selectedPeriodKey: Binding<String?>
    ) -> some View {
        let series = Array(points)
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(colors.secondaryText)
            if series.isEmpty {
                Text("No data in scope.")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            } else {
                Chart {
                    ForEach(series) { point in
                        if point.insufficientData {
                            BarMark(
                                x: .value("Period", point.key),
                                y: .value("Insufficient", 1)
                            )
                            .foregroundStyle(colors.fillSecondary.opacity(0.5))
                            .cornerRadius(3)
                            .opacity(barOpacity(for: point, selectedKey: selectedPeriodKey.wrappedValue))
                        } else if let adherence = point.adherencePercent {
                            BarMark(
                                x: .value("Period", point.key),
                                y: .value("Adherence", adherence)
                            )
                            .foregroundStyle(barFill(for: point, selectedKey: selectedPeriodKey.wrappedValue))
                            .cornerRadius(3)
                            .opacity(barOpacity(for: point, selectedKey: selectedPeriodKey.wrappedValue))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: chartFrameHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title) compliance trend chart")
                .accessibilityValue(trendAccessibilitySummary(series))
                .chartYScale(domain: 0 ... 100, range: .plotDimension(endPadding: 6))
                .chartXScale(range: .plotDimension(padding: 6), type: .category)
                .chartPlotStyle { plotArea in
                    plotArea.padding(.leading, YAxisLayout.plotLeadingGap)
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(colors.divider.opacity(0.6))
                        AxisValueLabel {
                            if let percent = value.as(Int.self) {
                                Text("\(percent)%")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(colors.tertiaryText)
                                    .frame(width: YAxisLayout.labelColumnWidth, alignment: .trailing)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel(centered: true, collisionResolution: .greedy) {
                            if let key = value.as(String.self) {
                                Text(TradingRulesComplianceTrendAxisFormat.axisLabel(for: key, period: period))
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundStyle(
                                        selectedPeriodKey.wrappedValue == key
                                            ? colors.primaryText
                                            : colors.tertiaryText
                                    )
                                    .fontWeight(selectedPeriodKey.wrappedValue == key ? .semibold : .regular)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                    }
                }
                .chartXSelection(value: selectedPeriodKey)

                if let key = selectedPeriodKey.wrappedValue,
                   let point = series.first(where: { $0.key == key })
                {
                    TradingRulesTrendPeriodDetailCard(
                        periodTitle: title,
                        point: point,
                        onDismiss: { selectedPeriodKey.wrappedValue = nil }
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if layout == .standard {
                    ForEach(series, id: \.id) { point in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(point.label)
                                    .experienceStyle(.caption2, color: colors.secondaryText)
                                Spacer()
                                Text(
                                    point.insufficientData
                                        ? "Insufficient data"
                                        : point.adherencePercent.map { String(format: "%.1f%%", $0) } ?? "–"
                                )
                                .experienceStyle(.caption2, color: colors.primaryText)
                                .monospacedDigit()
                            }
                            Text("\(point.evaluated) evaluated · \(point.violations) violations")
                                .experienceStyle(.caption2, color: colors.tertiaryText)
                            if let note = point.coverageNote {
                                Text(note)
                                    .experienceStyle(.caption2, color: colors.loss.opacity(0.85))
                            }
                        }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedPeriodKey.wrappedValue)
    }

    private func trendAccessibilitySummary(_ series: [TradingRulesComplianceAnalytics.TrendPoint]) -> String {
        let evaluable = series.filter { !$0.insufficientData && $0.adherencePercent != nil }
        guard !evaluable.isEmpty else { return "Insufficient data in scope." }
        let avg = evaluable.compactMap(\.adherencePercent).reduce(0, +) / Double(evaluable.count)
        return String(format: "Average adherence %.0f percent across %d periods.", avg, evaluable.count)
    }

    private func barFill(for point: TradingRulesComplianceAnalytics.TrendPoint, selectedKey: String?) -> Color {
        let baseOpacity = point.insufficientData ? 0.28 : 0.88
        let selected = selectedKey == point.key
        return colors.profit.opacity(selected ? min(1, baseOpacity + 0.12) : baseOpacity)
    }

    private func barOpacity(for point: TradingRulesComplianceAnalytics.TrendPoint, selectedKey: String?) -> Double {
        guard let selectedKey else { return 1 }
        return selectedKey == point.key ? 1 : 0.42
    }
}

/// Presentation-only period labels from trend bucket keys (does not affect aggregation).
private enum TradingRulesComplianceTrendAxisFormat {
    enum Period {
        case weekly
        case monthly
    }

    private static let weekStartFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM"
        return formatter
    }()

    static func axisLabel(for key: String, period: Period) -> String {
        switch period {
        case .weekly:
            return weekStartLabel(from: key)
        case .monthly:
            return monthLabel(from: key)
        }
    }

    private static func weekStartLabel(from key: String) -> String {
        guard let date = parseDateKey(key, requiresDay: true) else {
            return shortFallback(key)
        }
        return weekStartFormatter.string(from: date)
    }

    private static func monthLabel(from key: String) -> String {
        guard let date = parseDateKey(key, requiresDay: false) else {
            return shortFallback(key)
        }
        return monthFormatter.string(from: date)
    }

    private static func parseDateKey(_ key: String, requiresDay: Bool) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        if requiresDay {
            guard parts.count >= 3 else { return nil }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = requiresDay ? parts[2] : 1
        return calendar.date(from: components)
    }

    private static func shortFallback(_ key: String) -> String {
        String(key.prefix(10))
    }
}
