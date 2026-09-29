import Charts
import SwiftUI

struct AdminUsageLineChartSection: View {
    let title: String
    let subtitle: String
    let points: [AdminUsageDailyCount]
    var periodTotal: Int?
    var periodAverage: Double?

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text(title)
                    .experienceStyle(.headline, color: colors.primaryText)
                Text(subtitle)
                    .experienceStyle(.caption, color: colors.tertiaryText)
            }
            if let periodTotal {
                HStack(spacing: ExperienceSpacing.md) {
                    metricChip(label: "Period total", value: NumberDisplay.integer(periodTotal))
                    if let periodAverage {
                        metricChip(
                            label: "Avg / day",
                            value: NumberDisplay.decimal(periodAverage, minimumFractionDigits: 1, maximumFractionDigits: 1)
                        )
                    }
                }
            }
            if chartPoints.isEmpty {
                Text("No data for this range.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
            } else {
                Chart(chartPoints) { point in
                    LineMark(
                        x: .value("Day", point.date),
                        y: .value("Count", point.count)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(colors.accent)
                    PointMark(
                        x: .value("Day", point.date),
                        y: .value("Count", point.count)
                    )
                    .foregroundStyle(colors.accent)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .frame(height: 180)
            }
        }
        .padding(ExperienceSpacing.md)
        .experienceFloatingPanelBackground(
            in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
        )
    }

    private var chartPoints: [ChartPoint] {
        points.compactMap { row in
            guard let date = AdminUsageChartDate.parse(row.day) else { return nil }
            return ChartPoint(date: date, count: max(0, row.count))
        }
    }

    private func metricChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .experienceStyle(.caption2, color: colors.tertiaryText)
            Text(value)
                .experienceStyle(.subheadline, color: colors.primaryText)
                .fontWeight(.semibold)
        }
    }
}

private struct ChartPoint: Identifiable {
    var id: Date { date }
    var date: Date
    var count: Int
}

enum AdminUsageChartDate {
    static func parse(_ day: String) -> Date? {
        let trimmed = day.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.date(from: DateComponents(year: y, month: m, day: d))
    }
}
