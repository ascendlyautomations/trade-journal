import type { TradingPreferenceGlobal } from "@/lib/analytics/tradingPreferences"

export type TradingRuleTemplateId =
  | "scalper"
  | "day_trader"
  | "prop_firm"
  | "custom"

export type TradingRuleTemplateSuggestion = Partial<
  Omit<TradingPreferenceGlobal, "userId" | "updatedAt">
>

export type TradingRuleTemplate = {
  id: TradingRuleTemplateId
  label: string
  description: string
  /** Suggested values only — never persisted until the trader saves. */
  values: TradingRuleTemplateSuggestion
}

const WEEKDAYS = [
  "monday",
  "tuesday",
  "wednesday",
  "thursday",
  "friday",
] as const

export const TRADING_RULE_TEMPLATES: readonly TradingRuleTemplate[] = [
  {
    id: "scalper",
    label: "Scalper",
    description: "Higher trade count, short holds, core NY liquidity windows.",
    values: {
      tradingStyle: "scalper",
      preferredSessions: ["NY AM", "NY Lunch"],
      maxTradesPerDay: 25,
      minAcceptableRr: 1,
      maxContractsPerTrade: 4,
      allowedTradingDays: [...WEEKDAYS],
      plannedStartMinute: 9 * 60 + 30,
      plannedEndMinute: 12 * 60,
    },
  },
  {
    id: "day_trader",
    label: "Day Trader",
    description: "Session-based entries with a modest daily cap and weekday focus.",
    values: {
      tradingStyle: "day_trader",
      preferredSessions: ["NY AM", "NY PM"],
      maxTradesPerDay: 8,
      targetRr: 2,
      minAcceptableRr: 1.5,
      allowedTradingDays: [...WEEKDAYS],
      plannedStartMinute: 9 * 60 + 30,
      plannedEndMinute: 16 * 60,
    },
  },
  {
    id: "prop_firm",
    label: "Prop Firm Trader",
    description: "Daily/weekly loss limits, profit stop, and per-trade risk caps.",
    values: {
      tradingStyle: null,
      maxTradesPerDay: 6,
      dailyLossLimit: 500,
      dailyProfitTarget: 500,
      stopAfterDailyProfitTarget: true,
      maxWeeklyLoss: 1500,
      maxRiskPerTrade: 150,
      maxContractsPerTrade: 10,
      allowedTradingDays: [...WEEKDAYS],
      maxTradesPerDayScope: "combined",
      dailyLossLimitScope: "combined",
      dailyProfitRulesScope: "combined",
      maxWeeklyLossScope: "combined",
    },
  },
  {
    id: "custom",
    label: "Custom",
    description: "Start from your current rules without applying template values.",
    values: {},
  },
]

export function tradingRuleTemplateById(
  id: TradingRuleTemplateId
): TradingRuleTemplate | undefined {
  return TRADING_RULE_TEMPLATES.find((row) => row.id === id)
}
