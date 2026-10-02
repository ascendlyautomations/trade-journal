/**
 * Post-purchase continuation — conservative automatic retries.
 */

import type { ProFeatureKind, ProGateReason } from "./proGateReason"

export type ProUpgradeRetryAction =
  | { kind: "open_route"; path: string }
  | { kind: "resume_create_account"; draftKey?: string }
  | { kind: "none" }

export function isSafeAutomaticRetry(action: ProUpgradeRetryAction): boolean {
  switch (action.kind) {
    case "open_route":
    case "resume_create_account":
      return true
    case "none":
      return false
  }
}

/** Destructive / duplicate-sensitive flows must not auto-submit after upgrade. */
export const PRO_UPGRADE_MANUAL_RETRY_ACTIONS = new Set([
  "save_trade",
  "save_post",
  "save_clip",
  "send_dm",
  "csv_import_commit",
  "copy_trade_insert",
] as const)

const FEATURE_SAFE_ROUTES: Partial<Record<ProFeatureKind, string>> = {
  ai_analyst: "/analyst",
  backtest_lab: "/backtest",
  prop_firm: "/analytics/propfirm",
  copy_trading: "/settings",
  premium_analytics: "/dashboard",
  trading_reports: "/dashboard",
  performance_exports: "/dashboard",
}

/** Safe navigation-only continuation after confirmed Pro (never auto-submit). */
export function safeRetryForProGateReason(
  reason: ProGateReason
): ProUpgradeRetryAction {
  if (reason.type !== "feature") return { kind: "none" }
  const path = FEATURE_SAFE_ROUTES[reason.feature]
  if (!path) return { kind: "none" }
  return { kind: "open_route", path }
}
