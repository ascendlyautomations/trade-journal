import SwiftUI

// MARK: - Layout primitives

struct PropFirmDetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text(title)
                .experienceStyle(.footnote, color: colors.tertiaryText)
                .textCase(.uppercase)
                .tracking(0.5)
            content()
        }
    }
}

struct PropFirmDetailCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @Environment(\.themeColors) private var colors

    var body: some View {
        content()
            .padding(ExperienceSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.fillSecondary.opacity(0.5), in: RoundedRectangle(
                cornerRadius: ExperienceRadius.md,
                style: .continuous
            ))
    }
}

struct PropFirmDetailMetricTile: View {
    let title: String
    let primaryValue: String
    var secondaryValue: String?
    var tone: DashboardMetricTone = .neutral

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text(title)
                .experienceStyle(.caption2, color: colors.secondaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(primaryValue)
                .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(toneColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let secondaryValue {
                Text(secondaryValue)
                    .experienceStyle(.caption, color: colors.tertiaryText)
            }
        }
        .padding(ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.fillSecondary.opacity(0.65), in: RoundedRectangle(
            cornerRadius: ExperienceRadius.sm,
            style: .continuous
        ))
    }

    private var toneColor: Color {
        switch tone {
        case .neutral: return colors.primaryText
        case .positive: return colors.profit
        case .negative: return colors.loss
        }
    }
}

// MARK: - Hero

struct PropFirmDetailHeroView: View {
    let snapshot: PropFirmStatusSnapshot
    let contentPlan: PropFirmDetailContentPlan

    @Environment(\.themeColors) private var colors

    var body: some View {
        PropFirmDetailCard {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        if !snapshot.firmName.isEmpty, snapshot.firmName != snapshot.accountName {
                            Text(snapshot.firmName)
                                .experienceStyle(.headline, color: colors.primaryText)
                        }
                        Text(snapshot.accountName)
                            .experienceStyle(.subheadline, color: colors.secondaryText)
                    }
                    Spacer(minLength: 0)
                    statusBadge
                }

                HStack(spacing: ExperienceSpacing.md) {
                    liveMetric("Balance", DashboardViewModel.money(snapshot.currentBalance))
                    liveMetric("Cycle P&L", DashboardViewModel.money(snapshot.cyclePnL), tone: snapshot.cyclePnL >= 0 ? .positive : .negative)
                    liveMetric(
                        "To floor",
                        DashboardViewModel.money(snapshot.distanceToDD),
                        tone: snapshot.distanceDanger || snapshot.distanceToDD < 0 ? .negative : .positive
                    )
                }

                FlowLayoutTags(tags: summaryTags)
            }
        }
    }

    private var statusBadge: some View {
        Text(snapshot.statusLabel)
            .font(.system(.caption2, design: .rounded).weight(.bold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor.opacity(0.14), in: Capsule())
    }

    private var badgeColor: Color {
        switch snapshot.riskTone {
        case .positive: return colors.profit
        case .negative: return colors.loss
        case .neutral: return colors.accent
        }
    }

    private var summaryTags: [(String, BannerTone)] {
        contentPlan.heroSummaryTags()
    }

    private func liveMetric(_ label: String, _ value: String, tone: DashboardMetricTone = .neutral) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .experienceStyle(.caption2, color: colors.secondaryText)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(tone == .positive ? colors.profit : tone == .negative ? colors.loss : colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FlowLayoutTags: View {
    let tags: [(String, BannerTone)]

    @Environment(\.themeColors) private var colors

    var body: some View {
        FlowLayout(spacing: ExperienceSpacing.xs) {
            ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                ExperienceTag(title: tag.0, tone: tag.1)
            }
        }
    }
}

/// Simple wrapping horizontal stack for chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var frames: [CGRect] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}

// MARK: - At a glance

struct PropFirmAtAGlanceView: View {
    let lines: [PropFirmDetailPresentation.GlanceLine]

    @Environment(\.themeColors) private var colors

    var body: some View {
        PropFirmDetailSection(title: "At a glance") {
            PropFirmDetailCard {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                    ForEach(lines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.sm) {
                            Image(systemName: icon(for: line.tone))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(iconColor(for: line.tone))
                                .frame(width: 18, alignment: .center)
                            Text(line.text)
                                .experienceStyle(.subheadline, color: colors.primaryText)
                        }
                    }
                }
            }
        }
    }

    private func icon(for tone: PropFirmDetailPresentation.GlanceTone) -> String {
        switch tone {
        case .positive: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .neutral: return "info.circle.fill"
        }
    }

    private func iconColor(for tone: PropFirmDetailPresentation.GlanceTone) -> Color {
        switch tone {
        case .positive: return colors.profit
        case .warning: return colors.warning
        case .neutral: return colors.secondaryText
        }
    }
}

// MARK: - Drawdown

struct PropFirmDrawdownVisualView: View {
    let snapshot: PropFirmStatusSnapshot

    @Environment(\.themeColors) private var colors

    var body: some View {
        PropFirmDetailSection(title: "Drawdown") {
            PropFirmDetailCard {
                VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                    if let limit = snapshot.maxDrawdownLimit, limit > 0 {
                        labelValue("Maximum Drawdown", DashboardViewModel.money(limit))
                    }
                    labelValue(
                        "Drawdown Type",
                        PropFirmDetailPresentation.drawdownTypeLabel(snapshot.drawdownType)
                    )

                    if let footnote = PropFirmDetailPresentation.drawdownTypeFootnote(snapshot.drawdownType) {
                        Text(footnote)
                            .experienceStyle(.footnote, color: colors.secondaryText)
                    }

                    drawdownBar

                    VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                        balanceRow("Cycle start", snapshot.cycleStartBalance)
                        balanceRow("Peak balance", snapshot.peakBalance)
                        balanceRow("Drawdown floor", snapshot.drawdownFloor, emphasis: true)
                        balanceRow("Current balance", snapshot.currentBalance)
                    }

                    if snapshot.drawdownType?.usesTrailingCycleFloor == true {
                        Text("The floor rises when balance makes a new peak, staying max drawdown below the peak.")
                            .experienceStyle(.footnote, color: colors.secondaryText)
                    }

                    if snapshot.isFailed {
                        Text(PropFirmDetailPresentation.drawdownBreachMessage(type: snapshot.drawdownType))
                            .experienceStyle(.footnote, color: colors.loss)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var drawdownBar: some View {
        let low = min(snapshot.drawdownFloor, snapshot.cycleStartBalance)
        let high = max(snapshot.peakBalance, snapshot.currentBalance, low + 1)
        let span = max(high - low, 1)
        let floorRatio = NSDecimalNumber(decimal: (snapshot.drawdownFloor - low) / span).doubleValue
        let balanceRatio = NSDecimalNumber(decimal: (snapshot.currentBalance - low) / span).doubleValue
        let floorClamped = min(max(floorRatio, 0), 1)
        let balanceClamped = min(max(balanceRatio, 0), 1)

        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(colors.fillSecondary.opacity(0.8))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(colors.accent.opacity(0.35))
                        .frame(width: geo.size.width * balanceClamped)
                    Rectangle()
                        .fill(colors.warning.opacity(0.9))
                        .frame(width: 2)
                        .offset(x: geo.size.width * floorClamped - 1)
                }
            }
            .frame(height: 10)
            HStack {
                Text("Floor")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                Spacer()
                Text("Peak")
                    .experienceStyle(.caption2, color: colors.tertiaryText)
            }
        }
    }

    private func labelValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .experienceStyle(.caption2, color: colors.secondaryText)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(colors.primaryText)
        }
    }

    private func balanceRow(_ label: String, _ amount: Decimal, emphasis: Bool = false) -> some View {
        HStack {
            Text(label)
                .experienceStyle(.callout, color: colors.secondaryText)
            Spacer()
            Text(DashboardViewModel.money(amount))
                .font(.system(.callout, design: .rounded).weight(emphasis ? .bold : .semibold).monospacedDigit())
                .foregroundStyle(emphasis ? colors.warning : colors.primaryText)
        }
    }
}

// MARK: - Consistency

struct PropFirmConsistencyVisualView: View {
    let snapshot: PropFirmStatusSnapshot

    @Environment(\.themeColors) private var colors

    var body: some View {
        PropFirmDetailSection(title: "Consistency") {
            PropFirmDetailCard {
                if snapshot.consistencyRequired, let pct = snapshot.consistencyPercent {
                    HStack(spacing: ExperienceSpacing.lg) {
                        consistencyRing(percentCap: pct)
                        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                            Text("\(NumberDisplay.decimal(pct, maximumFractionDigits: 0))%")
                                .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                                .foregroundStyle(colors.primaryText)
                            Text("Max single winning trade share of total win profits")
                                .experienceStyle(.footnote, color: colors.secondaryText)
                            HStack(spacing: ExperienceSpacing.sm) {
                                ExperienceTag(
                                    title: snapshot.consistencyMet ? "Passing" : "Failing",
                                    tone: snapshot.consistencyMet ? .success : .warning
                                )
                                if snapshot.consistencyTotalProfit > 0 {
                                    Text("Largest win \(DashboardViewModel.money(snapshot.consistencyBiggestWin))")
                                        .experienceStyle(.caption, color: colors.tertiaryText)
                                }
                            }
                        }
                    }
                } else {
                    HStack(spacing: ExperienceSpacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(colors.profit)
                        Text("No consistency rule")
                            .experienceStyle(.body, color: colors.primaryText)
                    }
                }
            }
        }
    }

    private func consistencyRing(percentCap: Decimal) -> some View {
        let usage: Double = {
            guard snapshot.consistencyAllowedMax > 0 else { return 0 }
            let ratio = NSDecimalNumber(decimal: snapshot.consistencyBiggestWin / snapshot.consistencyAllowedMax).doubleValue
            return min(max(ratio, 0), 1)
        }()
        let tint = snapshot.consistencyMet ? colors.profit : colors.warning

        return ZStack {
            Circle()
                .stroke(colors.fillSecondary, lineWidth: 8)
            Circle()
                .trim(from: 0, to: usage)
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 72, height: 72)
        .accessibilityLabel("Consistency usage")
    }
}

// MARK: - Rule rows

struct PropFirmTradingRulesView: View {
    let snapshot: PropFirmStatusSnapshot
    let contentPlan: PropFirmDetailContentPlan

    @Environment(\.themeColors) private var colors

    var body: some View {
        let rows = contentPlan.tradingRuleRows()
        if !rows.isEmpty {
            PropFirmDetailSection(title: "Trading rules") {
                PropFirmDetailCard {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            PropFirmRuleRowView(row: row)
                            if index < rows.count - 1 {
                                Divider().opacity(0.35)
                            }
                        }
                    }
                }
            }
        }
    }

}

struct PropFirmRuleRow: Hashable {
    enum Status: Hashable {
        case met
        case pending
        case violation
        case neutral
    }

    var topic: PropFirmDetailRuleTopic
    var icon: String
    var label: String
    var value: String
    var status: Status
}

struct PropFirmRuleRowView: View {
    let row: PropFirmRuleRow

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            Image(systemName: row.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(colors.secondaryText)
                .frame(width: 22)
            Text(row.label)
                .experienceStyle(.callout, color: colors.secondaryText)
            Spacer(minLength: 8)
            Text(row.value)
                .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(colors.primaryText)
            statusIcon
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch row.status {
        case .met:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(colors.profit)
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(colors.secondaryText)
        case .violation:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(colors.loss)
        case .neutral:
            EmptyView()
        }
    }
}

// MARK: - Payouts

struct PropFirmDetailPayoutsView: View {
    let snapshot: PropFirmStatusSnapshot
    let contentPlan: PropFirmDetailContentPlan
    var onRecordPayout: () -> Void
    var recordPayoutEnabled: Bool

    @Environment(\.themeColors) private var colors

    var body: some View {
        PropFirmDetailSection(title: "Payouts") {
            PropFirmDetailCard {
                VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                    if snapshot.isFunded {
                        eligibilityHeader
                        if !payoutRequirementRows.isEmpty {
                            requirementsGrid
                        }
                        if snapshot.supportsRecordPayout {
                            Button(action: onRecordPayout) {
                                Label("Record Payout", systemImage: "dollarsign.circle")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .disabled(!recordPayoutEnabled)
                            .accessibilityIdentifier("propFirm.recordPayout")
                        }
                        FundedPayoutCycleHistoryContent(cycles: snapshot.completedPayoutHistory)
                    } else {
                        Text("Payout recording applies after the account is set to Funded mode.")
                            .experienceStyle(.footnote, color: colors.secondaryText)
                    }
                }
            }
        }
    }

    private var eligibilityHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Eligibility")
                    .experienceStyle(.caption2, color: colors.secondaryText)
                Text(snapshot.payoutReady ? "Ready" : "Not yet")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(snapshot.payoutReady ? colors.profit : colors.primaryText)
            }
            Spacer()
            if let behavior = PropFirmDetailPresentation.payoutDrawdownBehaviorTitle(snapshot.payoutDrawdownBehaviorRaw) {
                ExperienceTag(title: behavior, tone: .info)
            }
        }
    }

    private var payoutRequirementRows: [PropFirmDetailPresentation.PayoutRequirementRow] {
        contentPlan.payoutRequirementRows()
    }

    private var requirementsGrid: some View {
        VStack(spacing: ExperienceSpacing.xs) {
            ForEach(payoutRequirementRows) { row in
                HStack {
                    Image(systemName: row.met ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(row.met ? colors.profit : colors.secondaryText)
                    Text(row.title)
                        .experienceStyle(.subheadline, color: colors.primaryText)
                    Spacer()
                    if let detail = row.detail {
                        Text(detail)
                            .experienceStyle(.caption, color: colors.tertiaryText)
                    }
                }
            }
        }
    }
}

// MARK: - Journey

struct PropFirmJourneyStepperView: View {
    let title: String
    let steps: [PropFirmDetailPresentation.JourneyStep]

    @Environment(\.themeColors) private var colors

    var body: some View {
        PropFirmDetailSection(title: title) {
            PropFirmDetailCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(step.isComplete ? colors.profit : step.isCurrent ? colors.accent : colors.fillSecondary)
                                    .frame(width: 10, height: 10)
                                if index < steps.count - 1 {
                                    Rectangle()
                                        .fill(colors.border.opacity(0.5))
                                        .frame(width: 2)
                                        .frame(maxHeight: .infinity)
                                        .padding(.vertical, 2)
                                }
                            }
                            .frame(width: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title)
                                    .experienceStyle(.subheadline, color: colors.primaryText)
                                    .fontWeight(step.isCurrent ? .semibold : .regular)
                                if let subtitle = step.subtitle {
                                    Text(subtitle)
                                        .experienceStyle(.caption, color: colors.secondaryText)
                                }
                            }
                            .padding(.bottom, index < steps.count - 1 ? ExperienceSpacing.sm : 0)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Expandable rules

struct PropFirmExpandableRulesView: View {
    let rules: [PropFirmDetailPresentation.ExpandableRule]

    @Environment(\.themeColors) private var colors
    @State private var expandedIDs: Set<String> = []

    var body: some View {
        PropFirmDetailSection(title: "Important rules") {
            PropFirmDetailCard {
                VStack(spacing: 0) {
                    ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expandedIDs.contains(rule.id) {
                                    expandedIDs.remove(rule.id)
                                } else {
                                    expandedIDs.insert(rule.id)
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                                HStack {
                                    Text(rule.title)
                                        .experienceStyle(.subheadline, color: colors.primaryText)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Image(systemName: expandedIDs.contains(rule.id) ? "chevron.up" : "chevron.down")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(colors.tertiaryText)
                                }
                                if expandedIDs.contains(rule.id) {
                                    Text(rule.body)
                                        .experienceStyle(.footnote, color: colors.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if index < rules.count - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Evaluation metrics grid

struct PropFirmEvaluationMetricsView: View {
    let snapshot: PropFirmStatusSnapshot

    private let columns = [
        GridItem(.flexible(), spacing: ExperienceSpacing.sm),
        GridItem(.flexible(), spacing: ExperienceSpacing.sm),
    ]

    var body: some View {
        PropFirmDetailSection(title: snapshot.isFunded ? "Cycle targets" : "Evaluation") {
            LazyVGrid(columns: columns, spacing: ExperienceSpacing.sm) {
                if let target = snapshot.profitTarget, target > 0 {
                    PropFirmDetailMetricTile(
                        title: "Profit target",
                        primaryValue: DashboardViewModel.money(target),
                        secondaryValue: PropFirmDetailPresentation.formattedPercentOfAccount(
                            amount: target,
                            accountSize: snapshot.configuredAccountSize
                        ),
                        tone: snapshot.isPassed ? .positive : .neutral
                    )
                }
                if let maxDD = snapshot.maxDrawdownLimit, maxDD > 0 {
                    PropFirmDetailMetricTile(
                        title: "Max drawdown",
                        primaryValue: DashboardViewModel.money(maxDD),
                        secondaryValue: PropFirmDetailPresentation.formattedPercentOfAccount(
                            amount: maxDD,
                            accountSize: snapshot.configuredAccountSize
                        ),
                        tone: snapshot.isFailed ? .negative : .neutral
                    )
                }
                if let daily = snapshot.dailyLossLimit, daily > 0 {
                    PropFirmDetailMetricTile(
                        title: "Daily loss",
                        primaryValue: DashboardViewModel.money(daily),
                        secondaryValue: PropFirmDetailPresentation.formattedPercentOfAccount(
                            amount: daily,
                            accountSize: snapshot.configuredAccountSize
                        ),
                        tone: snapshot.dailyDrawdownBreached ? .negative : .neutral
                    )
                }
                if let required = snapshot.winningDaysRequired, required > 0 {
                    PropFirmDetailMetricTile(
                        title: "Winning days",
                        primaryValue: "\(snapshot.winningDays)/\(required)",
                        secondaryValue: snapshot.winningDaysTargetMet ? "Requirement met" : "In progress",
                        tone: snapshot.winningDaysTargetMet ? .positive : .neutral
                    )
                }
            }

            if let target = snapshot.profitTarget, target > 0 {
                PropFirmDetailCard {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Progress to target")
                                .experienceStyle(.caption2, color: colorsCaption)
                            Spacer()
                            Text("\(Int(snapshot.profitTargetProgress.rounded()))%")
                                .font(.system(.caption2, design: .rounded).weight(.semibold).monospacedDigit())
                        }
                        ProgressView(value: min(max(snapshot.profitTargetProgress / 100, 0), 1))
                            .tint(snapshot.isPassed ? colors.profit : colors.accent)
                    }
                }
            }
        }
    }

    @Environment(\.themeColors) private var colors
    private var colorsCaption: Color { colors.secondaryText }
}

struct PropFirmFundedLiveView: View {
    let snapshot: PropFirmStatusSnapshot

    @Environment(\.themeColors) private var colors

    var body: some View {
        PropFirmDetailSection(title: "Funded account") {
            PropFirmDetailCard {
                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    HStack {
                        label("Cycle start", DashboardViewModel.money(snapshot.cycleStartBalance))
                        Spacer()
                        label("Status", snapshot.statusLabel)
                    }
                    label("Cycle P&L", DashboardViewModel.money(snapshot.cyclePnL), tone: snapshot.cyclePnL >= 0 ? .positive : .negative)
                }
            }
        }
    }

    private func label(_ title: String, _ value: String, tone: DashboardMetricTone = .neutral) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .experienceStyle(.caption2, color: colors.secondaryText)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(tone == .positive ? colors.profit : tone == .negative ? colors.loss : colors.primaryText)
        }
    }
}
