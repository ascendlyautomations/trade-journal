import SwiftUI

// MARK: - Score ring

struct ScorecardScoreRingView: View {
    var score: Int?
    /// When overall is building, optional 0…1 fill for the gate progress.
    var buildingProgress: Double?
    /// When nil score and building, replaces the "Score" caption under the dash.
    var buildingCaption: String = "Building"
    /// Optional second line under "Building" (e.g. why composite is not ready).
    var buildingHint: String?
    var size: CGFloat = 96
    var lineWidth: CGFloat = 10

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedFill: Double = 0

    private var targetFill: Double {
        if let score { return Double(score) / 100 }
        if let buildingProgress { return min(max(buildingProgress, 0), 1) }
        return 0
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(colors.fillSecondary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: animatedFill)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                if let score {
                    Text("\(score)")
                        .font(.system(size: size * 0.28, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(colors.primaryText)
                        .contentTransition(.numericText())
                } else {
                    Text("—")
                        .font(.system(size: size * 0.22, weight: .semibold, design: .rounded))
                        .foregroundStyle(colors.secondaryText)
                }
                Text(score != nil ? "Score" : (buildingProgress != nil ? buildingCaption : "Score"))
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                if score == nil, let buildingHint, !buildingHint.isEmpty {
                    Text(buildingHint)
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: size * 1.05)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear { animateFill() }
        .onChange(of: targetFill) { _, _ in animateFill() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score.map { "Plan adherence score \($0) out of 100" } ?? "Score building")
    }

    private var ringColor: Color {
        if score != nil { return colors.accent }
        return colors.accentMuted
    }

    private func animateFill() {
        let target = targetFill
        guard !reduceMotion else {
            animatedFill = target
            return
        }
        withAnimation(.easeOut(duration: 0.55)) {
            animatedFill = target
        }
    }
}

// MARK: - Category progress bar

struct ScorecardCategoryBarRow: View {
    var title: String
    var valueLabel: String
    var fillFraction: Double
    var tint: Color
    /// When false, bar shows gate progress toward scoring (not a numeric score).
    var representsScore: Bool = true

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .experienceStyle(.caption, color: colors.secondaryText)
                Spacer(minLength: 4)
                Text(valueLabel)
                    .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(colors.primaryText)
            }
            progressTrack
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var clampedFill: Double {
        let raw = min(max(fillFraction, 0), 1)
        if representsScore, raw > 0, raw < 0.08 { return 0.08 }
        return raw
    }

    private var progressTrack: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(colors.fillTertiary)
            Capsule()
                .fill(tint.opacity(representsScore ? 1 : 0.9))
                .scaleEffect(x: clampedFill, y: 1, anchor: .leading)
        }
        .frame(height: 5)
        .accessibilityIdentifier("scorecard.bar.\(title)")
    }
}

// MARK: - Phase 1 icon indicators (Risk / Psychology)

struct ScorecardPhase1Indicator: View {
    enum Kind {
        case risk
        case psychology
    }

    var kind: Kind
    var coveragePercent: Int
    var caption: String

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            ZStack {
                Circle()
                    .fill(colors.fillSecondary)
                    .frame(width: 28, height: 28)
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.accent)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(shortTitle)
                    .experienceStyle(.caption2, color: colors.secondaryText)
                Text(caption)
                    .font(.system(.caption2, design: .rounded).weight(.medium).monospacedDigit())
                    .foregroundStyle(colors.primaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var iconName: String {
        switch kind {
        case .risk: return "shield.lefthalf.filled"
        case .psychology: return "brain.head.profile"
        }
    }

    private var shortTitle: String {
        switch kind {
        case .risk: return "Risk"
        case .psychology: return "Psych"
        }
    }
}

// MARK: - Compact metric tile (detail)

struct ScorecardMetricTile: View {
    var label: String
    var value: String
    var footnote: String?

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let footnote {
                Text(footnote)
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                    .lineLimit(1)
            }
        }
        .padding(ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(
            cornerRadius: ExperienceRadius.sm,
            style: .continuous
        ))
    }
}

// MARK: - Coverage mini chart (detail Risk / Psych)

struct ScorecardCoverageBarsView: View {
    struct Row: Identifiable {
        var id: String
        var label: String
        var fraction: Double
    }

    var rows: [Row]

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            ForEach(rows) { row in
                HStack(spacing: ExperienceSpacing.sm) {
                    Text(row.label)
                        .experienceStyle(.caption2, color: colors.secondaryText)
                        .frame(width: 72, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(colors.fillSecondary)
                            Capsule()
                                .fill(colors.accent.opacity(0.75))
                                .frame(width: geo.size.width * min(max(row.fraction, 0), 1))
                        }
                    }
                    .frame(height: 6)
                    Text(NumberDisplay.percent(row.fraction * 100, minimumFractionDigits: 0, maximumFractionDigits: 0))
                        .font(.system(.caption2, design: .rounded).monospacedDigit())
                        .foregroundStyle(colors.tertiaryText)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Home category snapshot (building composite)

struct ScorecardHomeCategorySnapshotGrid: View {
    let result: ScorecardResult

    @Environment(\.themeColors) private var colors

    private let columns = [
        GridItem(.flexible(), spacing: ExperienceSpacing.sm),
        GridItem(.flexible(), spacing: ExperienceSpacing.sm),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: ExperienceSpacing.sm) {
            ForEach(result.categories, id: \.id) { category in
                ScorecardMetricTile(
                    label: category.title,
                    value: ScorecardVisualSupport.homeSnapshotValue(category: category),
                    footnote: ScorecardVisualSupport.homeSnapshotFootnote(category: category)
                )
            }
        }
    }
}

// MARK: - Building gate chips (Home)

struct ScorecardGateChip: Identifiable, Hashable {
    var id: String
    var label: String
    var isMet: Bool
}

struct ScorecardGateChipsRow: View {
    var chips: [ScorecardGateChip]

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            ForEach(chipRows, id: \.self) { row in
                HStack(spacing: ExperienceSpacing.xs) {
                    ForEach(row) { chip in
                        chipView(chip)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chipRows: [[ScorecardGateChip]] {
        var history: [ScorecardGateChip] = []
        var tags: [ScorecardGateChip] = []
        var composite: [ScorecardGateChip] = []
        for chip in chips {
            switch chip.id {
            case "trades", "days": history.append(chip)
            case "composite": composite.append(chip)
            default: tags.append(chip)
            }
        }
        var rows: [[ScorecardGateChip]] = []
        if !history.isEmpty { rows.append(history) }
        if !tags.isEmpty { rows.append(tags) }
        if !composite.isEmpty { rows.append(composite) }
        return rows
    }

    private func chipView(_ chip: ScorecardGateChip) -> some View {
        HStack(spacing: 4) {
            Image(systemName: chip.isMet ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(chip.isMet ? colors.success : colors.tertiaryText)
            Text(chip.label)
                .experienceStyle(.caption2, color: chip.isMet ? colors.secondaryText : colors.primaryText)
                .fontWeight(chip.isMet ? .regular : .medium)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(colors.fillSecondary.opacity(0.65), in: Capsule())
    }
}

// MARK: - Helpers

enum ScorecardVisualSupport {
    static func buildingProgress(tradeCount: Int, tradingDayCount: Int) -> Double {
        let tradeGate = min(Double(tradeCount) / Double(ScorecardConstants.minTradesOverall), 1)
        let dayGate = min(Double(tradingDayCount) / Double(ScorecardConstants.minTradingDaysOverall), 1)
        return min(tradeGate, dayGate)
    }

    static func overallBuildingRingProgress(result: ScorecardResult) -> Double {
        let tradeCount = result.overall.tradeCount
        let tradingDayCount = result.overall.tradingDayCount
        let historyProgress = buildingProgress(tradeCount: tradeCount, tradingDayCount: tradingDayCount)
        let historyMet =
            tradeCount >= ScorecardConstants.minTradesOverall
            && tradingDayCount >= ScorecardConstants.minTradingDaysOverall
        guard historyMet else { return historyProgress }

        if !scoredCategories(for: result).isEmpty { return 1 }
        let tagProgress = result.categories
            .filter { $0.id == .consistency || $0.id == .discipline }
            .map { categoryBarFillFraction($0) }
            .max() ?? 0
        return tagProgress
    }

    static func overallBuildingGateChips(result: ScorecardResult) -> [ScorecardGateChip] {
        let tradeCount = result.overall.tradeCount
        let tradingDayCount = result.overall.tradingDayCount
        var chips: [ScorecardGateChip] = [
            ScorecardGateChip(
                id: "trades",
                label: "\(tradeCount)/\(ScorecardConstants.minTradesOverall) trades",
                isMet: tradeCount >= ScorecardConstants.minTradesOverall
            ),
            ScorecardGateChip(
                id: "days",
                label: "\(tradingDayCount)/\(ScorecardConstants.minTradingDaysOverall) days",
                isMet: tradingDayCount >= ScorecardConstants.minTradingDaysOverall
            ),
        ]

        if let consistency = result.categories.first(where: { $0.id == .consistency }),
           consistency.score == nil
        {
            let postLossTagged = postLossScorePoolCount(consistency)
            chips.append(
                ScorecardGateChip(
                    id: "post_loss_tags",
                    label: "\(postLossTagged)/\(ScorecardPlanAdherence.minPostLossPlanTagged) post-loss tags",
                    isMet: postLossTagged >= ScorecardPlanAdherence.minPostLossPlanTagged
                )
            )
        }
        if let discipline = result.categories.first(where: { $0.id == .discipline }),
           discipline.score == nil
        {
            let tagged = planTaggedTradeCount(discipline)
            chips.append(
                ScorecardGateChip(
                    id: "plan_tags",
                    label: "\(tagged)/\(ScorecardDiscipline.minPlanTaggedForScore) plan tags",
                    isMet: tagged >= ScorecardDiscipline.minPlanTaggedForScore
                )
            )
        }

        return chips
    }

    static func categoryFillFraction(_ category: ScorecardCategoryResult) -> Double {
        categoryBarFillFraction(category)
    }

    /// Bar fill: scored categories use 0…100 score; unscored use progress toward tag gates (never day/% coverage).
    static func categoryBarFillFraction(_ category: ScorecardCategoryResult) -> Double {
        if let score = category.score { return Double(score) / 100 }
        switch category.id {
        case .consistency:
            let pool = postLossScorePoolCount(category)
            return min(Double(pool) / Double(ScorecardPlanAdherence.minPostLossPlanTagged), 1)
        case .discipline:
            let tagged = planTaggedTradeCount(category)
            return min(Double(tagged) / Double(ScorecardDiscipline.minPlanTaggedForScore), 1)
        case .risk, .psychology:
            return 0
        }
    }

    static func categoryBarRepresentsScore(_ category: ScorecardCategoryResult) -> Bool {
        category.score != nil
    }

    static func homeSnapshotValue(category: ScorecardCategoryResult) -> String {
        switch category.id {
        case .risk:
            return "\(category.coveragePercent)%"
        case .psychology:
            if let matched = category.subMetrics.first(where: { $0.id == "psych.matched_days" }) {
                return "\(matched.value)d"
            }
            return "\(category.coveragePercent)%"
        case .consistency:
            if let score = category.score { return "\(score)/100" }
            let pool = postLossScorePoolCount(category)
            return "\(pool)/\(ScorecardPlanAdherence.minPostLossPlanTagged) tags"
        case .discipline:
            if let score = category.score { return "\(score)/100" }
            let tagged = planTaggedTradeCount(category)
            return tagged >= ScorecardDiscipline.minPlanTaggedForScore
                ? "Scoring…"
                : "\(tagged)/\(ScorecardDiscipline.minPlanTaggedForScore) tags"
        }
    }

    static func homeSnapshotFootnote(category: ScorecardCategoryResult) -> String? {
        switch category.id {
        case .risk: return "Data coverage"
        case .psychology: return "Matched check-ins"
        case .consistency:
            return category.score != nil ? category.reliability.label : "After-loss plan tags"
        case .discipline:
            return category.score != nil ? category.reliability.label : "Any plan tags"
        }
    }

    static func homeCategoryValueLabel(_ category: ScorecardCategoryResult) -> String {
        if let score = category.score { return "\(score)/100" }
        switch category.id {
        case .consistency:
            let pool = postLossScorePoolCount(category)
            return "— · \(pool)/\(ScorecardPlanAdherence.minPostLossPlanTagged) tags"
        case .discipline:
            let tagged = planTaggedTradeCount(category)
            if tagged < ScorecardDiscipline.minPlanTaggedForScore {
                return "— · \(tagged)/\(ScorecardDiscipline.minPlanTaggedForScore) tags"
            }
            return "—"
        case .risk, .psychology:
            return ScorecardDisplayStrings.categoryPhase1RowLabel(category: category)
        }
    }

    /// One-line reason the composite score is still hidden (history gates already met).
    static func overallBuildingHint(result: ScorecardResult) -> String? {
        guard result.overall.score == nil else { return nil }
        let tradeCount = result.overall.tradeCount
        let tradingDayCount = result.overall.tradingDayCount
        if tradeCount < ScorecardConstants.minTradesOverall
            || tradingDayCount < ScorecardConstants.minTradingDaysOverall
        {
            return nil
        }

        if scoredCategories(for: result).isEmpty { return "Tag plan on trades" }
        return nil
    }

    static func overallBuildingFootnote(result: ScorecardResult) -> String? {
        guard result.overall.score == nil else { return nil }
        let scored = scoredCategories(for: result)
        guard !scored.isEmpty else { return nil }
        let parts = scored.compactMap { cat -> String? in
            guard let score = cat.score else { return nil }
            switch cat.id {
            case .risk, .psychology: return nil
            case .consistency, .discipline: return "\(cat.title) \(score)/100"
            }
        }
        guard !parts.isEmpty else { return nil }
        return GeneratedProseNormalizer.normalize(
            parts.joined(separator: " · ") + " · Risk & Psych are insights only"
        )
    }

    private static func scoredCategories(for result: ScorecardResult) -> [ScorecardCategoryResult] {
        result.categories.filter {
            $0.score != nil && $0.eligible && $0.reliability != .insufficient
        }
    }

    static func categoryValueLabel(_ category: ScorecardCategoryResult) -> String {
        ScorecardDisplayStrings.categoryPhase1RowLabel(category: category)
    }

    static func postLossScorePoolCount(_ category: ScorecardCategoryResult) -> Int {
        if let scored = category.subMetrics.first(where: { $0.id == "consistency.scored_pool" }) {
            return scored.sampleSize
        }
        if let postLoss = category.subMetrics.first(where: { $0.id == "consistency.plan_after_loss" }) {
            return postLoss.sampleSize
        }
        if let window = category.subMetrics.first(where: { $0.id == "consistency.plan_after_three_losses" }) {
            return window.sampleSize
        }
        return 0
    }

    static func planTaggedTradeCount(_ category: ScorecardCategoryResult) -> Int {
        category.subMetrics.first(where: { $0.id == "discipline.plan_coverage" })?.sampleSize ?? 0
    }

    static func coverageRows(from category: ScorecardCategoryResult, maxRows: Int = 5) -> [ScorecardCoverageBarsView.Row] {
        category.subMetrics.prefix(maxRows).compactMap { metric in
            if metric.id == "psych.matched_days", let count = Int(metric.value.trimmingCharacters(in: .whitespaces)) {
                let denom = max(category.coveragePercent, 1)
                let fraction = min(Double(count) / Double(denom), 1)
                return ScorecardCoverageBarsView.Row(
                    id: metric.id,
                    label: "Matched",
                    fraction: fraction
                )
            }
            if metric.id == "psych.phase1_mode" { return nil }
            guard let parsed = parsePercent(metric.value) else { return nil }
            return ScorecardCoverageBarsView.Row(
                id: metric.id,
                label: shortMetricLabel(metric.label),
                fraction: parsed
            )
        }
    }

    static func metricTiles(from category: ScorecardCategoryResult, limit: Int = 6) -> [(label: String, value: String, footnote: String?)] {
        category.subMetrics.prefix(limit).map { metric in
            (shortMetricLabel(metric.label), metric.value, sampleFootnote(metric))
        }
    }

    private static func shortMetricLabel(_ label: String) -> String {
        if label.count <= 28 { return label }
        return String(label.prefix(26)) + "…"
    }

    private static func sampleFootnote(_ metric: ScorecardSubMetric) -> String? {
        guard metric.sampleSize > 0 else { return nil }
        return "n=\(metric.sampleSize)"
    }

    private static func parsePercent(_ value: String) -> Double? {
        let trimmed = value.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        guard let n = Double(trimmed) else { return nil }
        return n / 100
    }
}
