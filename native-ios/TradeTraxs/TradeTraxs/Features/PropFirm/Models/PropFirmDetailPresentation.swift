import Foundation

/// Detail-only formatting and glance lines derived from ``PropFirmStatusSnapshot``.
enum PropFirmDetailPresentation {
    enum GlanceTone: Hashable, Sendable {
        case positive
        case warning
        case neutral
    }

    struct GlanceLine: Hashable, Sendable, Identifiable {
        var id: String { text }
        var tone: GlanceTone
        var text: String
    }

    static func percentOfAccount(amount: Decimal, accountSize: Decimal) -> Double? {
        guard accountSize > 0, amount > 0 else { return nil }
        let ratio = NSDecimalNumber(decimal: amount / accountSize).doubleValue
        guard ratio.isFinite, ratio > 0 else { return nil }
        return min(ratio * 100, 999)
    }

    static func formattedPercentOfAccount(amount: Decimal, accountSize: Decimal) -> String? {
        guard let pct = percentOfAccount(amount: amount, accountSize: accountSize) else { return nil }
        return "\(Int(pct.rounded()))%"
    }

    static func payoutDrawdownBehaviorTitle(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw {
        case PayoutDrawdownBehavior.resetToAccount.rawValue:
            return "Reset to account balance"
        case PayoutDrawdownBehavior.keepTrailing.rawValue:
            return "Keep trailing floor"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func payoutDrawdownBehaviorDetail(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw {
        case PayoutDrawdownBehavior.resetToAccount.rawValue:
            return "After a payout, the drawdown floor resets to your account size (starting balance)."
        case PayoutDrawdownBehavior.keepTrailing.rawValue:
            return "After a payout, the trailing drawdown floor stays where it was at payout time."
        default:
            return nil
        }
    }

    static func glanceLines(for snapshot: PropFirmStatusSnapshot) -> [GlanceLine] {
        var lines: [GlanceLine] = []

        if snapshot.isFailed {
            lines.append(GlanceLine(tone: .warning, text: "Trailing drawdown breached"))
        } else if snapshot.distanceDanger {
            lines.append(GlanceLine(tone: .warning, text: "Close to drawdown floor"))
        }

        if snapshot.dailyDrawdownBreached {
            lines.append(GlanceLine(tone: .warning, text: "Daily loss limit breached"))
        } else if let daily = snapshot.dailyLossLimit, daily > 0 {
            lines.append(GlanceLine(tone: .neutral, text: "Daily loss limit \(NumberDisplay.money(daily))"))
        }

        if snapshot.consistencyRequired {
            if snapshot.consistencyMet {
                lines.append(GlanceLine(tone: .positive, text: "Consistency rule passing"))
            } else {
                if let pct = snapshot.consistencyPercent {
                    lines.append(
                        GlanceLine(
                            tone: .warning,
                            text: "\(NumberDisplay.decimal(pct, maximumFractionDigits: 0))% consistency rule active"
                        )
                    )
                } else {
                    lines.append(GlanceLine(tone: .warning, text: "Consistency rule failing"))
                }
            }
        } else {
            lines.append(GlanceLine(tone: .positive, text: "No consistency rule"))
        }

        if let required = snapshot.winningDaysRequired, required > 0 {
            let met = snapshot.winningDaysTargetMet
            lines.append(
                GlanceLine(
                    tone: met ? .positive : .neutral,
                    text: "Winning days \(snapshot.winningDays)/\(required)"
                )
            )
        }

        if snapshot.isFunded {
            if snapshot.payoutReady {
                lines.append(GlanceLine(tone: .positive, text: "Eligible to record payout"))
            }
        } else if snapshot.isPassed {
            lines.append(GlanceLine(tone: .positive, text: "Profit target reached"))
        }

        if let maxDD = snapshot.maxDrawdownLimit, maxDD > 0 {
            lines.append(
                GlanceLine(
                    tone: .neutral,
                    text: "Trailing max drawdown \(NumberDisplay.money(maxDD))"
                )
            )
        }

        return lines
    }

    struct PayoutRequirementRow: Hashable, Sendable, Identifiable {
        var id: String { title }
        var title: String
        var met: Bool
        var detail: String?
    }

    static func payoutRequirements(for snapshot: PropFirmStatusSnapshot) -> [PayoutRequirementRow] {
        guard snapshot.isFunded else { return [] }
        var rows: [PayoutRequirementRow] = []

        if snapshot.profitTargetConfigured {
            rows.append(
                PayoutRequirementRow(
                    title: "Profit target",
                    met: snapshot.isPassed,
                    detail: snapshot.profitTarget.map { NumberDisplay.money($0) }
                )
            )
        }

        if let required = snapshot.winningDaysRequired, required > 0 {
            rows.append(
                PayoutRequirementRow(
                    title: "Winning days",
                    met: snapshot.winningDaysTargetMet,
                    detail: "\(snapshot.winningDays) of \(required)"
                )
            )
        }

        if snapshot.consistencyRequired {
            rows.append(
                PayoutRequirementRow(
                    title: "Consistency",
                    met: snapshot.consistencyMet,
                    detail: snapshot.consistencyPercent.map {
                        "Max \(NumberDisplay.decimal($0, maximumFractionDigits: 0))% of win profits"
                    }
                )
            )
        }

        if let daily = snapshot.dailyLossLimit, daily > 0 {
            rows.append(
                PayoutRequirementRow(
                    title: "Daily loss limit",
                    met: !snapshot.dailyDrawdownBreached,
                    detail: NumberDisplay.money(daily)
                )
            )
        }

        rows.append(
            PayoutRequirementRow(
                title: "Trailing drawdown",
                met: !snapshot.isFailed,
                detail: snapshot.maxDrawdownLimit.map { NumberDisplay.money($0) }
            )
        )

        return rows
    }

    struct JourneyStep: Hashable, Sendable, Identifiable {
        var id: String { title }
        var title: String
        var subtitle: String?
        var isComplete: Bool
        var isCurrent: Bool
    }

    static func journeySteps(for snapshot: PropFirmStatusSnapshot) -> [JourneyStep] {
        if snapshot.isFunded {
            var steps: [JourneyStep] = [
                JourneyStep(
                    title: "Funded account",
                    subtitle: snapshot.statusLabel,
                    isComplete: true,
                    isCurrent: false
                ),
            ]

            if snapshot.profitTargetConfigured || (snapshot.winningDaysRequired ?? 0) > 0 || snapshot.consistencyRequired {
                let cycleMet = snapshot.isPassed
                    && snapshot.winningDaysTargetMet
                    && (!snapshot.consistencyRequired || snapshot.consistencyMet)
                    && !snapshot.dailyDrawdownBreached
                    && !snapshot.isFailed
                steps.append(
                    JourneyStep(
                        title: "Meet cycle requirements",
                        subtitle: cycleMet ? "Requirements met" : "In progress",
                        isComplete: cycleMet,
                        isCurrent: !cycleMet && !snapshot.payoutReady
                    )
                )
            }

            steps.append(
                JourneyStep(
                    title: "Eligible for payout",
                    subtitle: snapshot.payoutReady ? "Ready" : "Not yet",
                    isComplete: snapshot.payoutReady,
                    isCurrent: snapshot.payoutReady
                )
            )

            steps.append(
                JourneyStep(
                    title: "Record payout",
                    subtitle: snapshot.completedPayoutHistory.isEmpty ? "Closes cycle" : "History below",
                    isComplete: !snapshot.completedPayoutHistory.isEmpty,
                    isCurrent: false
                )
            )
            return steps
        }

        return [
            JourneyStep(
                title: "Evaluation",
                subtitle: snapshot.statusLabel,
                isComplete: snapshot.isPassed,
                isCurrent: !snapshot.isPassed && !snapshot.isFailed
            ),
            JourneyStep(
                title: "Pass requirements",
                subtitle: passRequirementsSubtitle(snapshot),
                isComplete: snapshot.isPassed && snapshot.winningDaysTargetMet
                    && (!snapshot.consistencyRequired || snapshot.consistencyMet)
                    && !snapshot.dailyDrawdownBreached,
                isCurrent: !snapshot.isPassed
            ),
            JourneyStep(
                title: "Funded",
                subtitle: "Switch mode when your firm funds you",
                isComplete: false,
                isCurrent: snapshot.isPassed
            ),
            JourneyStep(
                title: "Payout eligible",
                subtitle: "After funded + cycle rules",
                isComplete: false,
                isCurrent: false
            ),
        ]
    }

    private static func passRequirementsSubtitle(_ snapshot: PropFirmStatusSnapshot) -> String {
        var parts: [String] = []
        if snapshot.profitTargetConfigured {
            parts.append("Profit target")
        }
        if let required = snapshot.winningDaysRequired, required > 0 {
            parts.append("Winning days")
        }
        if snapshot.consistencyRequired {
            parts.append("Consistency")
        }
        if parts.isEmpty { return "Rules on this account" }
        return parts.joined(separator: " · ")
    }

    struct ExpandableRule: Hashable, Sendable, Identifiable {
        var id: String { title }
        var title: String
        var body: String
    }

    static func expandableRules(for snapshot: PropFirmStatusSnapshot) -> [ExpandableRule] {
        var rules: [ExpandableRule] = []

        if let title = payoutDrawdownBehaviorTitle(snapshot.payoutDrawdownBehaviorRaw),
           let detail = payoutDrawdownBehaviorDetail(snapshot.payoutDrawdownBehaviorRaw) {
            rules.append(ExpandableRule(title: "Payout drawdown behavior", body: "\(title). \(detail)"))
        }

        if let threshold = snapshot.winningDayThreshold, threshold > 0 {
            rules.append(
                ExpandableRule(
                    title: "Winning day threshold",
                    body: "A futures day counts as a winning day when net P&L is at least \(NumberDisplay.money(threshold))."
                )
            )
        } else if (snapshot.winningDaysRequired ?? 0) > 0 {
            rules.append(
                ExpandableRule(
                    title: "Winning day threshold",
                    body: "A futures day counts as a winning day when net P&L is positive."
                )
            )
        }

        if snapshot.consistencyRequired, let pct = snapshot.consistencyPercent {
            rules.append(
                ExpandableRule(
                    title: "Consistency rule",
                    body: "Your largest winning trade must stay at or below \(NumberDisplay.decimal(pct, maximumFractionDigits: 0))% of total profit from winning trades this cycle."
                )
            )
        }

        if let note = snapshot.accountNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            rules.append(ExpandableRule(title: "Account note", body: note))
        }

        rules.append(
            ExpandableRule(
                title: "Trailing drawdown",
                body: "Drawdown is tracked from the peak balance in this cycle. If balance falls below the floor (peak minus max drawdown), the account fails the trailing rule."
            )
        )

        return rules
    }
}
