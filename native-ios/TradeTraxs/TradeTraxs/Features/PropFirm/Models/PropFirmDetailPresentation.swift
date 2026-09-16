import Foundation

/// Detail-only formatting and glance lines derived from ``PropFirmStatusSnapshot``.
nonisolated enum PropFirmDetailPresentation {
    enum GlanceTone: Hashable, Sendable {
        case positive
        case warning
        case neutral
    }

    struct GlanceLine: Hashable, Sendable, Identifiable {
        var topic: PropFirmDetailRuleTopic
        var tone: GlanceTone
        var text: String
        var id: String { String(describing: topic) }
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

    static func drawdownTypeLabel(_ type: PropFirmDrawdownType?) -> String {
        type?.displayName ?? "Unspecified"
    }

    static func drawdownTypeFootnote(_ type: PropFirmDrawdownType?) -> String? {
        type?.conciseFootnote
    }

    static func drawdownBreachMessage(type: PropFirmDrawdownType?) -> String {
        switch type {
        case .intradayTrailing, .endOfDayTrailing:
            return "Trailing drawdown rule breached."
        case .staticThreshold:
            return "Maximum drawdown rule breached."
        case nil:
            return "Maximum drawdown rule breached."
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
        PropFirmDetailContentPlan(snapshot: snapshot).glanceLines()
    }

    struct PayoutRequirementRow: Hashable, Sendable, Identifiable {
        var topic: PropFirmDetailRuleTopic
        var title: String
        var met: Bool
        var detail: String?
        var id: String { String(describing: topic) }
    }

    static func payoutRequirements(for snapshot: PropFirmStatusSnapshot) -> [PayoutRequirementRow] {
        PropFirmDetailContentPlan(snapshot: snapshot).payoutRequirementRows()
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
        var topic: PropFirmDetailRuleTopic
        var title: String
        var body: String
        var id: String { String(describing: topic) }
    }

    static func expandableRules(for snapshot: PropFirmStatusSnapshot) -> [ExpandableRule] {
        PropFirmDetailContentPlan(snapshot: snapshot).expandableRules()
    }
}
