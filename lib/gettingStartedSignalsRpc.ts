/**
 * RPC wire shape for rpc_v1_getting_started_signals.
 */

import type { GettingStartedChecklistSignals } from "./gettingStartedChecklistSignals.types.ts"

export type GettingStartedSignalsRpcWire = {
  onboarding_completed: boolean
  has_seen_getting_started_intro: boolean
  has_seen_onboarding_complete_popup: boolean
  trade_count: number
  profile_post_count: number
  follow_count: number
  has_ever_joined_other_room: boolean
  has_public_trade: boolean
  first_private_trade_id: string | null
}

export function decodeGettingStartedSignalsRpc(
  raw: unknown
): GettingStartedChecklistSignals {
  if (!raw || typeof raw !== "object") {
    throw new Error("GettingStartedSignalsRpc: invalid payload")
  }
  const row = raw as Partial<GettingStartedSignalsRpcWire>
  return {
    onboardingCompleted: row.onboarding_completed === true,
    hasSeenGettingStartedIntro: row.has_seen_getting_started_intro === true,
    hasSeenOnboardingCompletePopup:
      row.has_seen_onboarding_complete_popup === true,
    tradeCount:
      typeof row.trade_count === "number" && row.trade_count >= 0
        ? row.trade_count
        : 0,
    profilePostCount:
      typeof row.profile_post_count === "number" && row.profile_post_count >= 0
        ? row.profile_post_count
        : 0,
    followCount:
      typeof row.follow_count === "number" && row.follow_count >= 0
        ? row.follow_count
        : 0,
    hasEverJoinedOtherRoom: row.has_ever_joined_other_room === true,
    hasPublicTrade: row.has_public_trade === true,
    firstPrivateTradeId:
      typeof row.first_private_trade_id === "string"
        ? row.first_private_trade_id
        : row.first_private_trade_id != null
          ? String(row.first_private_trade_id)
          : null,
  }
}
