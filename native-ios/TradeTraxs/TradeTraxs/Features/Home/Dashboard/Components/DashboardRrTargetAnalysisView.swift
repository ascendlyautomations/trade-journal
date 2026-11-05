import SwiftUI

// MARK: - Copy / recommendations (presentation only; engine unchanged)

private enum RrTargetDashboardCopy {
    static func recommendation(for analysis: DashboardRrTargetAnalysis) -> String {
        func finish(_ text: String) -> String { GeneratedProseNormalizer.normalize(text) }

        guard analysis.pairedCount > 0 else {
            return finish("Log Target R:R and Max R:R on the same trade to compare plan vs extension.")
        }

        let target = analysis.avgTargetRr
        let maxRan = analysis.avgMaxRrReached
        let targetR = decimalDouble(target)
        let maxR = decimalDouble(maxRan)

        if analysis.pairedCount >= DashboardRrTargetAnalysis.minPairedRecommend,
           let insight = compactEngineInsight(analysis.bullets)
        {
            return finish(insight)
        }

        if targetR > 0, maxR > 0 {
            let ratio = maxR / targetR
            let targetLabel = formatR(target)
            let maxLabel = formatR(maxRan)
            let trailLabel = formatR(
                Decimal(suggestedTrailR(target: targetR, maxRan: maxR, attainment: ratio))
            )

            if ratio < 0.85 {
                let prefix = analysis.pairedCount < DashboardRrTargetAnalysis.minPairedRecommend
                    ? "Early read · "
                    : ""
                return finish(
                    "\(prefix)Extension averages ~\(maxLabel) vs ~\(targetLabel) targets, consider planning ~\(trailLabel), partials, or a trail near where price typically peaks."
                )
            }
            if ratio >= 1.0 {
                return finish(
                    "Extension often meets or beats targets, check whether exits capture that run or targets could be modestly higher."
                )
            }
        }

        if analysis.pairedCount < DashboardRrTargetAnalysis.minPairedRecommend {
            let need = DashboardRrTargetAnalysis.minPairedRecommend - analysis.pairedCount
            return finish(
                "Add \(need) more paired trade\(need == 1 ? "" : "s") (target + max on each) for a sharper suggestion."
            )
        }

        return finish(
            analysis.bullets.first.map { shorten($0, max: 180) }
                ?? "Keep logging target and max R:R on the same trades to refine exit planning."
        )
    }

    private static func compactEngineInsight(_ bullets: [String]) -> String? {
        let preferred = bullets.first { line in
            line.localizedCaseInsensitiveContains("exits planned nearer")
                || line.localizedCaseInsensitiveContains("consider whether")
                || line.localizedCaseInsensitiveContains("partials or trails")
                || line.localizedCaseInsensitiveContains("price often reversed")
        }
        let line = preferred ?? bullets.first
        return line.map { shorten(stripNoise($0), max: 180) }
    }

    private static func stripNoise(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in [
            "Early read (small sample): ",
            "In this paired sample, ",
        ] {
            if s.hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return s
    }

    private static func suggestedTrailR(target: Double, maxRan: Double, attainment: Double) -> Double {
        let fromAttainment = target * attainment * 2
        let rounded = (max(fromAttainment, maxRan) * 10).rounded() / 10
        return max(0.5, min(rounded, target))
    }

    private static func shorten(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        return String(text.prefix(max - 1)) + "…"
    }

    private static func formatR(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return NumberDisplay.ratio(value, fractionDigits: 1)
    }

    private static func decimalDouble(_ value: Decimal?) -> Double {
        guard let value else { return 0 }
        return NSDecimalNumber(decimal: value).doubleValue
    }
}

struct DashboardRrTargetAnalysisView: View {
    let analysis: DashboardRrTargetAnalysis

    @Environment(\.themeColors) private var colors

    var body: some View {
        Group {
            if analysis.pairedCount == 0 {
                emptyState
            } else {
                pairedState
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.rrTargeting")
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            HStack(spacing: ExperienceSpacing.md) {
                ZStack {
                    Circle()
                        .fill(colors.fillSecondary)
                        .frame(width: 44, height: 44)
                    Image(systemName: "scope")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(colors.accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pair target & max R:R")
                        .experienceStyle(.subheadline, color: colors.primaryText)
                        .fontWeight(.semibold)
                    Text("Same trade · both fields")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                }
            }
            HStack(spacing: ExperienceSpacing.xs) {
                sampleChip("\(analysis.tradeCount) in scope", met: analysis.tradeCount > 0)
                sampleChip("0 paired", met: false)
            }
            recommendationCard(text: RrTargetDashboardCopy.recommendation(for: analysis))
        }
    }

    // MARK: - Paired

    private var pairedState: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            HStack(spacing: ExperienceSpacing.sm) {
                sampleChip("\(analysis.pairedCount) paired", met: true)
                if analysis.tradeCount > analysis.pairedCount {
                    let excluded = analysis.tradeCount - analysis.pairedCount
                    sampleChip("\(excluded) need both fields", met: false)
                }
            }

            HStack(alignment: .top, spacing: ExperienceSpacing.lg) {
                comparisonBars
                if let attainment = analysis.avgTargetAttainmentRatio {
                    attainmentRing(ratio: attainment)
                }
            }

            extensionGapSummary

            recommendationCard(text: RrTargetDashboardCopy.recommendation(for: analysis))
        }
    }

    private var comparisonBars: some View {
        let target = decimalDouble(analysis.avgTargetRr)
        let maxRan = decimalDouble(analysis.avgMaxRrReached)
        let scale = max(target, maxRan, 0.01)

        return VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            comparisonRow(label: "Avg Target", value: target, scale: scale, tint: colors.accentMuted)
            comparisonRow(label: "Max reached", value: maxRan, scale: scale, tint: colors.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func comparisonRow(label: String, value: Double, scale: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                Spacer(minLength: 4)
                Text(NumberDisplay.ratio(Decimal(value), fractionDigits: 2))
                    .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(colors.primaryText)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(colors.fillTertiary)
                Capsule()
                    .fill(tint)
                    .scaleEffect(x: min(value / scale, 1), y: 1, anchor: .leading)
            }
            .frame(height: 6)
        }
    }

    @ViewBuilder
    private var extensionGapSummary: some View {
        let target = decimalDouble(analysis.avgTargetRr)
        let maxRan = decimalDouble(analysis.avgMaxRrReached)
        if target > 0, maxRan >= 0 {
            let fill = min(maxRan / target, 1)
            let gap = max(target - maxRan, 0)
            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                HStack {
                    Text(gapSummaryTitle(gap: gap, target: target, maxRan: maxRan))
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .fontWeight(.medium)
                    Spacer(minLength: 0)
                    if gap > 0.05 {
                        Text("−\(NumberDisplay.ratio(Decimal(gap), fractionDigits: 1))")
                            .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(colors.warning)
                    } else if maxRan > target + 0.05 {
                        Text("+\(NumberDisplay.ratio(Decimal(maxRan - target), fractionDigits: 1))")
                            .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(colors.success)
                    }
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(colors.fillTertiary)
                    Capsule()
                        .fill(gap > 0.05 ? colors.warning.opacity(0.35) : colors.accent.opacity(0.85))
                        .scaleEffect(x: max(fill, 0.02), y: 1, anchor: .leading)
                }
                .frame(height: 8)
                HStack {
                    Text("0R")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                    Spacer()
                    Text("Avg target")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                }
            }
            .accessibilityIdentifier("dashboard.rrTargeting.gap")
        }
    }

    private func gapSummaryTitle(gap: Double, target: Double, maxRan: Double) -> String {
        if gap > 0.05 {
            return "Extension usually stops before target"
        }
        if maxRan > target + 0.05 {
            return "Extension often runs past target"
        }
        return "Extension aligns with target"
    }

    private func attainmentRing(ratio: Decimal) -> some View {
        let raw = min(max(NSDecimalNumber(decimal: ratio).doubleValue, 0), 1.5)
        let ringFill = min(raw, 1)
        let pct = Int((NSDecimalNumber(decimal: ratio * 100)).doubleValue.rounded())

        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(colors.fillSecondary, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: ringFill)
                    .stroke(colors.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(pct)%")
                    .font(.system(.caption, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(colors.primaryText)
            }
            .frame(width: 56, height: 56)
            Text("vs target")
                .experienceStyle(.caption2, color: colors.tertiaryText)
        }
    }

    private func recommendationCard(text: String) -> some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(colors.accent)
                .padding(.top, 2)
            Text(text)
                .experienceStyle(.caption, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
        .accessibilityIdentifier("dashboard.rrTargeting.recommendation")
    }

    private func sampleChip(_ label: String, met: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(met ? colors.success : colors.tertiaryText)
            Text(label)
                .experienceStyle(.caption2, color: met ? colors.secondaryText : colors.primaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(colors.fillSecondary.opacity(0.55), in: Capsule())
    }

    private func decimalDouble(_ value: Decimal?) -> Double {
        guard let value else { return 0 }
        return NSDecimalNumber(decimal: value).doubleValue
    }
}
