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

    var body: some View {
        VStack(alignment: .leading, spacing: layout == .compact ? ExperienceSpacing.sm : ExperienceSpacing.md) {
            trendBlock(
                title: "Weekly Compliance",
                points: weekly.suffix(8),
                period: .weekly,
                selectedPeriodKey: $selectedWeeklyKey
            )
            trendBlock(
                title: "Monthly Compliance",
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
        let seriesKeys = series.map(\.key)
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
                .accessibilityHint("Select a bar to view period details.")
                .chartYScale(domain: 0 ... 100, range: .plotDimension(endPadding: 6))
                .chartXScale(domain: seriesKeys, range: .plotDimension(padding: 0))
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(colors.divider.opacity(0.6))
                        AxisValueLabel {
                            if let percent = value.as(Int.self) {
                                Text("\(percent)%")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(colors.tertiaryText)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(preset: .aligned, values: seriesKeys) { value in
                        AxisValueLabel(centered: true, collisionResolution: .greedy) {
                            if let key = value.as(String.self) {
                                Text(
                                    TradingRulesComplianceTrendAxisFormat.axisLabel(
                                        for: key,
                                        period: period,
                                        peerKeys: seriesKeys
                                    )
                                )
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
                        periodKind: period,
                        peerKeys: seriesKeys,
                        point: point,
                        onDismiss: { selectedPeriodKey.wrappedValue = nil }
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
enum TradingRulesComplianceTrendAxisFormat {
    enum Period {
        case weekly
        case monthly
    }

    private static let easternTimeZone = TimeZone(identifier: "America/New_York")!

    private static var easternCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = easternTimeZone
        return calendar
    }

    private static let weekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = easternTimeZone
        formatter.dateFormat = "M/d"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = easternTimeZone
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private static let monthWithYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = easternTimeZone
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    static func axisLabel(for key: String, period: Period, peerKeys: [String]) -> String {
        displayLabel(for: key, period: period, peerKeys: peerKeys, style: .axis)
    }

    static func displayLabel(for key: String, period: Period, peerKeys: [String]) -> String {
        displayLabel(for: key, period: period, peerKeys: peerKeys, style: .detail)
    }

    private enum LabelStyle {
        case axis
        case detail
    }

    private static func displayLabel(
        for key: String,
        period: Period,
        peerKeys: [String],
        style: LabelStyle
    ) -> String {
        let spansMultipleYears = distinctYears(in: peerKeys).count > 1
        switch period {
        case .weekly:
            guard let date = parseDateKey(key, requiresDay: true) else {
                return shortFallback(key)
            }
            return weekFormatter.string(from: date)
        case .monthly:
            guard let date = parseDateKey(key, requiresDay: false) else {
                return shortFallback(key)
            }
            if spansMultipleYears {
                return style == .axis
                    ? monthWithYearFormatter.string(from: date)
                    : monthWithYearFormatter.string(from: date)
            }
            return monthFormatter.string(from: date)
        }
    }

    private static func distinctYears(in keys: [String]) -> Set<Int> {
        Set(
            keys.compactMap { key -> Int? in
                let parts = key.split(separator: "-")
                guard let year = parts.first.flatMap({ Int($0) }) else { return nil }
                return year
            }
        )
    }

    private static func parseDateKey(_ key: String, requiresDay: Bool) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        if requiresDay {
            guard parts.count >= 3 else { return nil }
        }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = requiresDay ? parts[2] : 1
        components.timeZone = easternTimeZone
        return easternCalendar.date(from: components)
    }

    private static func shortFallback(_ key: String) -> String {
        String(key.prefix(10))
    }
}