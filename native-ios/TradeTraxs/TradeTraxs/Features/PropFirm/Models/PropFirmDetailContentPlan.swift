import Foundation

/// Semantic identity for a prop-firm rule or detail line — dedupe by meaning, not string equality.
nonisolated enum PropFirmDetailRuleTopic: Hashable, Sendable {
    case accountSize
    case profitTarget
    case maxDrawdownLimit
    case maxDrawdownUsage
    case dailyLossLimit
    case dailyLossUsage
    case winningDaysRequirement
    case winningDayThreshold
    case winningDayThresholdExplanation
    case consistencyRule
    case trailingDrawdownGuide
    case trailingDrawdownBreachStatus
    case drawdownProximityAlert
    case dailyLossBreachStatus
    case payoutDrawdownBehavior
    case profitTargetReachedStatus
    case payoutEligibleStatus
    case accountNote
    case drawdownMethodology
}

/// Canonical detail presentation — registers authoritative sections first, then supplies deduped content.
nonisolated struct PropFirmDetailContentPlan: Sendable {
    let snapshot: PropFirmStatusSnapshot
    let showsDrawdownSection: Bool
    private(set) var claimedTopics: Set<PropFirmDetailRuleTopic> = []

    init(snapshot: PropFirmStatusSnapshot) {
        self.snapshot = snapshot
        self.showsDrawdownSection = snapshot.maxDrawdownLimit != nil || snapshot.drawdownFloor > 0
        registerAuthoritativeTopics()
    }

    func includes(_ topic: PropFirmDetailRuleTopic) -> Bool {
        claimedTopics.contains(topic)
    }

    mutating func claim(_ topic: PropFirmDetailRuleTopic) {
        claimedTopics.insert(topic)
    }

    /// Reserves topics for structured sections that appear later on the page (first claim wins).
    private mutating func registerAuthoritativeTopics() {
        if snapshot.configuredAccountSize > 0 {
            claim(.accountSize)
        }
        if snapshot.profitTargetConfigured {
            claim(.profitTarget)
        }
        if let max = snapshot.maxDrawdownLimit, max > 0 {
            claim(.maxDrawdownLimit)
        }
        if let daily = snapshot.dailyLossLimit, daily > 0 {
            claim(.dailyLossLimit)
        }
        if let required = snapshot.winningDaysRequired, required > 0 {
            claim(.winningDaysRequirement)
        }
        // Consistency section is always rendered on the detail page.
        claim(.consistencyRule)
        if showsDrawdownSection {
            claim(.trailingDrawdownGuide)
            if snapshot.drawdownType != nil {
                claim(.drawdownMethodology)
            }
            if snapshot.isFailed {
                claim(.trailingDrawdownBreachStatus)
            }
        }
        if let threshold = snapshot.winningDayThreshold, threshold > 0 {
            claim(.winningDayThreshold)
            claim(.winningDayThresholdExplanation)
        } else if (snapshot.winningDaysRequired ?? 0) > 0 {
            claim(.winningDayThresholdExplanation)
        }
        if PropFirmDetailPresentation.payoutDrawdownBehaviorTitle(snapshot.payoutDrawdownBehaviorRaw) != nil {
            claim(.payoutDrawdownBehavior)
        }
    }

    // MARK: - Section builders

    func heroSummaryTags() -> [(String, BannerTone)] {
        var tags: [(String, BannerTone)] = [(snapshot.phaseLabel, .info)]
        if !includes(.accountSize), snapshot.configuredAccountSize > 0 {
            tags.append((NumberDisplay.money(snapshot.configuredAccountSize), .info))
        }
        if !includes(.profitTarget), let target = snapshot.profitTarget, target > 0 {
            tags.append(("Target \(NumberDisplay.money(target))", .info))
        }
        if !includes(.maxDrawdownLimit), let maxDD = snapshot.maxDrawdownLimit, maxDD > 0 {
            tags.append(("DD \(NumberDisplay.money(maxDD))", .warning))
        }
        if let status = snapshot.publicStatusLabel, !status.isEmpty {
            tags.append((status, .success))
        }
        return tags
    }

    func glanceLines() -> [PropFirmDetailPresentation.GlanceLine] {
        var lines: [PropFirmDetailPresentation.GlanceLine] = []
        var seen: Set<PropFirmDetailRuleTopic> = []

        func append(
            _ topic: PropFirmDetailRuleTopic,
            tone: PropFirmDetailPresentation.GlanceTone,
            text: String
        ) {
            guard !includes(topic), !seen.contains(topic) else { return }
            seen.insert(topic)
            lines.append(
                PropFirmDetailPresentation.GlanceLine(
                    topic: topic,
                    tone: tone,
                    text: text
                )
            )
        }

        if snapshot.isFailed {
            append(.trailingDrawdownBreachStatus, tone: .warning, text: "Trailing drawdown breached")
        } else if snapshot.distanceDanger {
            append(.drawdownProximityAlert, tone: .warning, text: "Close to drawdown floor")
        }

        if snapshot.dailyDrawdownBreached {
            append(.dailyLossBreachStatus, tone: .warning, text: "Daily loss limit breached")
        }

        if snapshot.isFunded {
            if snapshot.payoutReady {
                append(.payoutEligibleStatus, tone: .positive, text: "Eligible to record payout")
            }
        } else if snapshot.isPassed {
            append(.profitTargetReachedStatus, tone: .positive, text: "Profit target reached")
        }

        return lines
    }

    func payoutRequirementRows() -> [PropFirmDetailPresentation.PayoutRequirementRow] {
        guard snapshot.isFunded else { return [] }
        var rows: [PropFirmDetailPresentation.PayoutRequirementRow] = []

        if !includes(.profitTarget), snapshot.profitTargetConfigured {
            rows.append(
                PropFirmDetailPresentation.PayoutRequirementRow(
                    topic: .profitTarget,
                    title: "Profit target",
                    met: snapshot.isPassed,
                    detail: snapshot.profitTarget.map { NumberDisplay.money($0) }
                )
            )
        }

        if !includes(.winningDaysRequirement), let required = snapshot.winningDaysRequired, required > 0 {
            rows.append(
                PropFirmDetailPresentation.PayoutRequirementRow(
                    topic: .winningDaysRequirement,
                    title: "Winning days",
                    met: snapshot.winningDaysTargetMet,
                    detail: "\(snapshot.winningDays) of \(required)"
                )
            )
        }

        if !includes(.consistencyRule), snapshot.consistencyRequired {
            rows.append(
                PropFirmDetailPresentation.PayoutRequirementRow(
                    topic: .consistencyRule,
                    title: "Consistency",
                    met: snapshot.consistencyMet,
                    detail: snapshot.consistencyPercent.map {
                        "Max \(NumberDisplay.decimal($0, maximumFractionDigits: 0))% of win profits"
                    }
                )
            )
        }

        if !includes(.dailyLossLimit), let daily = snapshot.dailyLossLimit, daily > 0 {
            rows.append(
                PropFirmDetailPresentation.PayoutRequirementRow(
                    topic: .dailyLossLimit,
                    title: "Daily loss limit",
                    met: !snapshot.dailyDrawdownBreached,
                    detail: NumberDisplay.money(daily)
                )
            )
        }

        if !includes(.maxDrawdownLimit) {
            rows.append(
                PropFirmDetailPresentation.PayoutRequirementRow(
                    topic: .maxDrawdownLimit,
                    title: "Trailing drawdown",
                    met: !snapshot.isFailed,
                    detail: snapshot.maxDrawdownLimit.map { NumberDisplay.money($0) }
                )
            )
        }

        return rows
    }

    func expandableRules() -> [PropFirmDetailPresentation.ExpandableRule] {
        var rules: [PropFirmDetailPresentation.ExpandableRule] = []
        var seen: Set<PropFirmDetailRuleTopic> = []

        func append(_ topic: PropFirmDetailRuleTopic, title: String, body: String) {
            guard !includes(topic), !seen.contains(topic) else { return }
            seen.insert(topic)
            rules.append(
                PropFirmDetailPresentation.ExpandableRule(
                    topic: topic,
                    title: title,
                    body: body
                )
            )
        }

        if let title = PropFirmDetailPresentation.payoutDrawdownBehaviorTitle(snapshot.payoutDrawdownBehaviorRaw),
           let detail = PropFirmDetailPresentation.payoutDrawdownBehaviorDetail(snapshot.payoutDrawdownBehaviorRaw) {
            append(.payoutDrawdownBehavior, title: "Payout drawdown behavior", body: "\(title). \(detail)")
        }

        if !includes(.winningDayThresholdExplanation) {
            if let threshold = snapshot.winningDayThreshold, threshold > 0 {
                append(
                    .winningDayThresholdExplanation,
                    title: "Winning day threshold",
                    body: "A futures day counts as a winning day when net P&L is at least \(NumberDisplay.money(threshold))."
                )
            } else if (snapshot.winningDaysRequired ?? 0) > 0 {
                append(
                    .winningDayThresholdExplanation,
                    title: "Winning day threshold",
                    body: "A futures day counts as a winning day when net P&L is positive."
                )
            }
        }

        if snapshot.consistencyRequired, let pct = snapshot.consistencyPercent {
            append(
                .consistencyRule,
                title: "Consistency rule",
                body: "Your largest winning trade must stay at or below \(NumberDisplay.decimal(pct, maximumFractionDigits: 0))% of total profit from winning trades this cycle."
            )
        }

        if let note = snapshot.accountNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            append(.accountNote, title: "Account note", body: note)
        }

        if !includes(.trailingDrawdownGuide), !includes(.drawdownMethodology) {
            append(
                .trailingDrawdownGuide,
                title: "Maximum drawdown",
                body: "Your firm sets the maximum drawdown limit and methodology on this account."
            )
        }

        return rules
    }

    func tradingRuleRows() -> [PropFirmRuleRow] {
        var rows: [PropFirmRuleRow] = []

        if !includes(.winningDaysRequirement), let required = snapshot.winningDaysRequired, required > 0 {
            rows.append(
                PropFirmRuleRow(
                    topic: .winningDaysRequirement,
                    icon: "calendar",
                    label: "Minimum winning days",
                    value: "\(snapshot.winningDays) / \(required)",
                    status: snapshot.winningDaysTargetMet ? .met : .pending
                )
            )
        }
        if !includes(.winningDayThreshold), let threshold = snapshot.winningDayThreshold, threshold > 0 {
            rows.append(
                PropFirmRuleRow(
                    topic: .winningDayThreshold,
                    icon: "sun.max",
                    label: "Winning day threshold",
                    value: NumberDisplay.money(threshold),
                    status: .neutral
                )
            )
        }
        if let daily = snapshot.dailyLossLimit, daily > 0 {
            if !includes(.dailyLossLimit) {
                rows.append(
                    PropFirmRuleRow(
                        topic: .dailyLossLimit,
                        icon: "chart.line.downtrend.xyaxis",
                        label: "Daily loss limit",
                        value: NumberDisplay.money(daily),
                        status: snapshot.dailyDrawdownBreached ? .violation : .neutral
                    )
                )
            }
            rows.append(
                PropFirmRuleRow(
                    topic: .dailyLossUsage,
                    icon: "gauge.with.dots.needle.50percent",
                    label: "Worst day loss (cycle)",
                    value: NumberDisplay.money(snapshot.dailyLossUsed),
                    status: snapshot.dailyDrawdownBreached ? .violation : .neutral
                )
            )
        }
        if let maxDD = snapshot.maxDrawdownLimit, maxDD > 0 {
            rows.append(
                PropFirmRuleRow(
                    topic: .maxDrawdownUsage,
                    icon: "arrow.down.to.line",
                    label: "Max drawdown used",
                    value: NumberDisplay.money(snapshot.maxDrawdownUsed),
                    status: snapshot.isFailed ? .violation : .neutral
                )
            )
        }
        return rows
    }

    var showsAccountSizeSection: Bool {
        snapshot.configuredAccountSize > 0
    }
}
