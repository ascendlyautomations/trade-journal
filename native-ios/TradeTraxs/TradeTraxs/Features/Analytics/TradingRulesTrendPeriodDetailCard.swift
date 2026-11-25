import SwiftUI

struct TradingRulesTrendPeriodDetailCard: View {
    let periodTitle: String
    let periodKind: TradingRulesComplianceTrendAxisFormat.Period
    let peerKeys: [String]
    let point: TradingRulesComplianceAnalytics.TrendPoint
    let onDismiss: () -> Void

    @Environment(\.themeColors) private var colors

    private var periodDisplayLabel: String {
        TradingRulesComplianceTrendAxisFormat.displayLabel(
            for: point.key,
            period: periodKind,
            peerKeys: peerKeys
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(periodTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                    Text(periodDisplayLabel)
                        .experienceStyle(.caption2, color: colors.secondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: ExperienceSpacing.sm)
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(colors.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss period details")
            }

            HStack(spacing: ExperienceSpacing.md) {
                metricColumn(
                    title: "Compliance",
                    value: point.insufficientData
                        ? "–"
                        : point.adherencePercent.map { String(format: "%.1f%%", $0) } ?? "–",
                    tone: colors.profit
                )
                metricColumn(title: "Evaluated", value: "\(point.evaluated)", tone: colors.primaryText)
                metricColumn(title: "Violations", value: "\(point.violations)", tone: colors.loss)
            }

            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text("\(point.followed) followed · \(point.unevaluatedChecks) unevaluated checks")
                    .experienceStyle(.caption2, color: colors.secondaryText)
                Text("\(point.tradeCount) trade\(point.tradeCount == 1 ? "" : "s") in this period")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            }

            if let note = point.coverageNote {
                Text(note)
                    .experienceStyle(.caption2, color: colors.warning)
                    .lineLimit(2)
            }
        }
        .padding(ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .experienceTradingRulesCard(cornerRadius: ExperienceRadius.md)
    }

    private func metricColumn(title: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .experienceStyle(.caption2, color: colors.tertiaryText)
            Text(value)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
