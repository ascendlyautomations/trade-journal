import { TRADETRAXS_FEATURE_LABELS } from "@/lib/tradeTraxsPlans"

/** Shown in analytics Pro upgrade surfaces for free-plan users. */
export const PRO_UPGRADE_ANALYTICS_HEADLINE = "Unlock TradeTraxs Pro"

export const PRO_UPGRADE_ANALYTICS_SUBHEADLINE =
  "You're currently using Basic Analytics."

export const PRO_UPGRADE_ANALYTICS_SECTION_LABEL = "Upgrade to unlock:"

/** Pro features listed in dashboard / analytics upgrade prompts. */
export const PRO_UPGRADE_ANALYTICS_FEATURES = [
  TRADETRAXS_FEATURE_LABELS.aiTradeAnalyst,
  "Backtesting Lab",
  TRADETRAXS_FEATURE_LABELS.propFirmMode,
  TRADETRAXS_FEATURE_LABELS.premiumAnalytics,
  "Trading Reports",
  "Session Performance",
  "Weekday Performance",
  "Trading Hours",
  "Hold Time",
  "Behavior Warnings",
  "Best Setups",
  "Advanced Risk Metrics",
] as const

/** Compact highlights for the free-dashboard Pro preview card. */
export const PRO_UPGRADE_PREVIEW_FEATURES = [
  TRADETRAXS_FEATURE_LABELS.aiTradeAnalyst,
  "Backtesting Lab",
  TRADETRAXS_FEATURE_LABELS.propFirmMode,
  "Trading Reports",
  "Advanced Performance Analytics",
  "Trading Behavior Insights",
  "Much More",
] as const

export const PRO_EXPORT_UPGRADE_TITLE = "Export Images"

export function proExportUpgradeDescription(proPlanName: string): string {
  return `Branded export cards are included with ${proPlanName}.`
}
