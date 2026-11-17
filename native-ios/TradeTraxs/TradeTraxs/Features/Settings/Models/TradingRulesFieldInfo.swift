import Foundation

/// Beginner-friendly copy for Trading Rules fields. Wording matches current analytics wiring.
enum TradingRulesFieldInfo: String, CaseIterable, Identifiable {
    case targetRr
    case maxTradesPerDay
    case dailyLossLimit
    case consecutiveLossPause
    case breakevenTolerance
    case minAcceptableRr
    case maxRiskPerTrade
    case maxContractsPerTrade
    case ruleTemplate
    case tradingStyle
    case preferredSessions
    case primaryInstruments
    case allowedTradingDays
    case dailyProfitTarget
    case stopAfterDailyProfitTarget
    case maxDrawdownGoal
    case maxWeeklyLoss
    case waitAfterLossMinutes
    case plannedStart
    case plannedEnd
    case tradingRuleScope
    case accountPicker
    case accountDailyLossLimit
    case accountDailyProfitTarget
    case accountMaxDrawdownGoal
    case personalComplianceGoal
    case applyRulesToPastTrades

    var id: String { rawValue }

    var title: String {
        switch self {
        case .targetRr: return "Target R:R"
        case .maxTradesPerDay: return "Maximum trades per day"
        case .dailyLossLimit: return "Daily loss limit"
        case .consecutiveLossPause: return "Consecutive losses before a break"
        case .breakevenTolerance: return "Breakeven tolerance"
        case .minAcceptableRr: return "Minimum acceptable R:R"
        case .maxRiskPerTrade: return "Maximum risk per trade"
        case .maxContractsPerTrade: return "Maximum contracts per trade"
        case .ruleTemplate: return "Rule template"
        case .tradingStyle: return "Trading style"
        case .preferredSessions: return "Preferred trading sessions"
        case .primaryInstruments: return "Primary instruments"
        case .allowedTradingDays: return "Allowed trading days"
        case .dailyProfitTarget: return "Daily profit target"
        case .stopAfterDailyProfitTarget: return "Stop after daily profit target"
        case .maxDrawdownGoal: return "Maximum drawdown goal"
        case .maxWeeklyLoss: return "Maximum weekly loss"
        case .waitAfterLossMinutes: return "Waiting time after a loss"
        case .plannedStart: return "Planned start"
        case .plannedEnd: return "Planned end"
        case .tradingRuleScope: return "Applies to"
        case .accountPicker: return "Account"
        case .accountDailyLossLimit: return "Daily loss limit"
        case .accountDailyProfitTarget: return "Daily profit target"
        case .accountMaxDrawdownGoal: return "Maximum drawdown goal"
        case .personalComplianceGoal: return "Personal compliance goal"
        case .applyRulesToPastTrades: return "Apply Rules to Past Trades"
        }
    }

    var body: String {
        switch self {
        case .targetRr:
            return "The reward multiple you plan to aim for on a trade. When enough trades have max R data, Performance and your scorecard can compare max R reached to this target."
        case .maxTradesPerDay:
            return "Your personal daily trade cap. Dashboard, reports, and Psychology Insights can flag days and trades beyond this count when it is set."
        case .dailyLossLimit:
            return "The dollar loss that counts as your daily stop. Compliance checks are event-based: the day is marked when cumulative losses cross the limit, and later trades that day can flag as post-limit. Trades before the breach are not scored as \"followed\" — only post-breach checks appear."
        case .consecutiveLossPause:
            return "How many priced losses in a row before you plan to pause. Compliance flags each new entry while the priced loss streak on that account is still at or above this count. A priced win resets the streak; breakeven and unpriced trades do not change it. There is no timed auto-reset in settings — only streak history."
        case .breakevenTolerance:
            return "A dollar band around zero for labeling breakeven trades. TradeTraxs stores this for you but does not use it in performance or psychology analytics today."
        case .minAcceptableRr:
            return "The lowest planned R:R you still consider acceptable at entry. Performance and reports compare this to each trade's planned R:R when that value is recorded."
        case .maxRiskPerTrade:
            return "Your personal dollar risk cap at entry. Analytics can only check this when trades record dollar risk at entry; P&L is not used as a substitute."
        case .maxContractsPerTrade:
            return "The largest contract or share size you allow on one trade. Analytics checks recorded size on each trade when this is set."
        case .ruleTemplate:
            return "Starter drafts for scalping, day trading, or prop-firm style limits. Applying fills the form only — nothing saves until you tap Save."
        case .tradingStyle:
            return "How you usually trade (scalper, day, or swing). This is saved on your profile for reference and is not used in analytics comparisons."
        case .preferredSessions:
            return "Sessions you plan to trade. Performance and weekly or monthly reports can compare results inside those sessions versus outside them."
        case .primaryInstruments:
            return "Symbols you focus on. Analytics can compare P&L on these symbols versus everything else when this list is not empty."
        case .allowedTradingDays:
            return "Weekdays you plan to trade in Eastern time. Leave empty to keep this rule off. Trades on other weekdays can be flagged in reports."
        case .dailyProfitTarget:
            return "A personal dollar goal for the day. When set, analytics can also measure trades taken after the target is reached if you turn on stop-after-target."
        case .stopAfterDailyProfitTarget:
            return "When on, compliance flags trades after your daily profit target is reached. Checks are event-based (post-target entries only) — not a followed/violated check on every trade before the target."
        case .maxDrawdownGoal:
            return "A personal drawdown goal in dollars. TradeTraxs saves it but does not use it in performance or psychology analytics today."
        case .maxWeeklyLoss:
            return "A dollar loss cap for an Eastern Monday-start week. Compliance marks the week when losses cross the cap; later trades may flag as post-limit. There is no per-trade \"followed\" check before the breach."
        case .waitAfterLossMinutes:
            return "Minimum minutes after a priced loss before your next entry on the same account. Compliance measures from that loss's exit time to your next entry. Missing exit times or overlapping timestamps stay unevaluated — never counted as violations."
        case .plannedStart, .plannedEnd:
            return "Your planned trading window in U.S. Eastern time. Performance and reports can compare trades inside this window versus outside it when both times are set."
        case .tradingRuleScope:
            return "All Accounts Combined adds trades across accounts before checking the rule. Per Account checks each account on its own."
        case .accountPicker:
            return "Pick which account gets custom dollar limits. Overrides apply only to that account; other rules stay global."
        case .accountDailyLossLimit:
            return "Replaces the global daily loss limit for this account in analytics when you enter an amount. Other accounts still use your global limit."
        case .accountDailyProfitTarget:
            return "A custom daily profit target for this account only. Profit-target and stop-after-target analytics respect this amount for the account."
        case .accountMaxDrawdownGoal:
            return "A custom drawdown goal for this account only. TradeTraxs saves it but does not use it in analytics calculations today."
        case .personalComplianceGoal:
            return "Target adherence percent for Discipline Progress on Trading Rules Analytics. Informational only — does not change how rules are scored."
        case .applyRulesToPastTrades:
            return "Analyze your previous trades using your current trading rules. When off, only trades made after your rules were configured count toward compliance."
        }
    }
}
