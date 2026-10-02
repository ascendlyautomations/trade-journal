import { devLog } from "./devLog.ts"
import type { ProGateReason } from "./proGateReason.ts"

export type MonetizationFunnelEvent =
  | "pro_gate_presented"
  | "trial_eligible"
  | "purchase_started"
  | "purchase_verified"
  | "entitlement_confirmed"
  | "purchase_failed"
  | "restore_started"
  | "restore_succeeded"

type MonetizationFunnelPayload = {
  event: MonetizationFunnelEvent
  reason?: ProGateReason
  platform?: "web" | "ios"
  trialEligible?: boolean
  detail?: string
}

/** Lightweight dev logging — no payment secrets or JWS payloads. */
export function logMonetizationFunnel(payload: MonetizationFunnelPayload): void {
  devLog("[monetization]", payload.event, {
    reason: payload.reason,
    platform: payload.platform,
    trialEligible: payload.trialEligible,
    detail: payload.detail,
  })
}
