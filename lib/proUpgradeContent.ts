import { TRADETRAXS_FEATURE_LABELS } from "@/lib/tradeTraxsPlans"

export const PRO_UPGRADE_ANALYTICS_HEADLINE = "Unlock TraxPro"

export const PRO_UPGRADE_ANALYTICS_SUBHEADLINE =
  "You're currently using basic dashboard analytics."

export const PRO_UPGRADE_ANALYTICS_SECTION_LABEL = "Upgrade to unlock:"

export const PRO_UPGRADE_ANALYTICS_FEATURES = [
  TRADETRAXS_FEATURE_LABELS.premiumAnalytics,
  TRADETRAXS_FEATURE_LABELS.advancedPropFirmAnalytics,
  TRADETRAXS_FEATURE_LABELS.aiTradeAnalystAndCoach,
  TRADETRAXS_FEATURE_LABELS.weeklyMonthlyReports,
  TRADETRAXS_FEATURE_LABELS.backtestLab,
  TRADETRAXS_FEATURE_LABELS.copyTradingGroups,
  TRADETRAXS_FEATURE_LABELS.unlimitedClips,
] as const

export const PRO_UPGRADE_PREVIEW_FEATURES = [
  TRADETRAXS_FEATURE_LABELS.premiumAnalytics,
  TRADETRAXS_FEATURE_LABELS.advancedPropFirmAnalytics,
  TRADETRAXS_FEATURE_LABELS.aiTradeAnalystAndCoach,
  "Trading reports",
  TRADETRAXS_FEATURE_LABELS.backtestLab,
  TRADETRAXS_FEATURE_LABELS.copyTradingGroups,
] as const

export const PRO_EXPORT_UPGRADE_TITLE = "Export Images"

export function proExportUpgradeDescription(proPlanName: string): string {
  return `Branded export cards are included with ${proPlanName}.`
}
