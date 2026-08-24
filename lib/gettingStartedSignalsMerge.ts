import type {
  GettingStartedChecklistSignals,
  GettingStartedLocalOverrides,
} from "./gettingStartedChecklistSignals.types.ts"

/** Merge trusted local Session/Dashboard/trades cache over RPC baseline. */
export function mergeGettingStartedSignals(
  baseline: GettingStartedChecklistSignals,
  overrides: GettingStartedLocalOverrides
): GettingStartedChecklistSignals {
  const next = { ...baseline }

  if (overrides.profile) {
    next.onboardingCompleted = overrides.profile.onboardingCompleted
    next.hasSeenGettingStartedIntro =
      overrides.profile.hasSeenGettingStartedIntro
    next.hasSeenOnboardingCompletePopup =
      overrides.profile.hasSeenOnboardingCompletePopup
  }

  if (overrides.trade) {
    next.tradeCount = overrides.trade.tradeCount
    next.hasPublicTrade = overrides.trade.hasPublicTrade
    next.firstPrivateTradeId = overrides.trade.firstPrivateTradeId
  } else if (
    overrides.dashboardTradeCount != null &&
    overrides.dashboardTradeCount >= 0
  ) {
    next.tradeCount = overrides.dashboardTradeCount
  }

  if (overrides.followCount != null && overrides.followCount >= 0) {
    next.followCount = overrides.followCount
  }

  return next
}
