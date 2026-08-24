import type { TradeChecklistSignals } from "./deriveTradeChecklistSignals.ts"

export type GettingStartedChecklistSignals = {
  onboardingCompleted: boolean
  hasSeenGettingStartedIntro: boolean
  hasSeenOnboardingCompletePopup: boolean
  tradeCount: number
  profilePostCount: number
  followCount: number
  hasEverJoinedOtherRoom: boolean
  hasPublicTrade: boolean
  /** Most recent private trade — used to deep-link into trade edit. */
  firstPrivateTradeId: string | null
}

/** Profile onboarding flags from UserProfileProvider — skips duplicate profiles query. */
export type GettingStartedPreloadedProfileSignals = {
  onboardingCompleted: boolean
  hasSeenGettingStartedIntro: boolean
  hasSeenOnboardingCompletePopup: boolean
}

export type GettingStartedLocalOverrides = {
  profile?: GettingStartedPreloadedProfileSignals
  trade?: TradeChecklistSignals | null
  dashboardTradeCount?: number | null
  followCount?: number | null
}
