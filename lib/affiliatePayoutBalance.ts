import type { SupabaseClient } from "@supabase/supabase-js"
import { AFFILIATE_PER_REFERRAL_EARNINGS } from "./affiliateEarnings"

export type AffiliatePayoutBalance = {
  referralCount: number
  perReferralEarnings: number
  totalEarnings: number
  totalPaid: number
  earningsSinceLastPayout: number
  pendingReserved: number
  approvedReserved: number
  availableToRequest: number
  lastPaidAt: string | null
  minimumPayout: number
  canRequest: boolean
}

function num(v: unknown): number {
  if (v == null) return 0
  const n = Number(v)
  return Number.isFinite(n) ? n : 0
}

function bool(v: unknown): boolean {
  if (typeof v === "boolean") return v
  if (v === "true") return true
  if (v === "false") return false
  return Boolean(v)
}

/** Normalize RPC payload (PostgREST may return json object or string; keys may vary). */
function unwrapRaw(raw: unknown): Record<string, unknown> | null {
  if (raw == null) return null
  if (typeof raw === "string") {
    try {
      const p = JSON.parse(raw) as unknown
      return typeof p === "object" && p !== null ? (p as Record<string, unknown>) : null
    } catch {
      return null
    }
  }
  if (typeof raw === "object") return raw as Record<string, unknown>
  return null
}

function pickNum(o: Record<string, unknown>, camel: string, snake: string): number {
  const a = o[camel]
  const b = o[snake]
  const v = a !== undefined && a !== null ? a : b
  return num(v)
}

function pickBool(o: Record<string, unknown>, camel: string, snake: string): boolean {
  const a = o[camel]
  const b = o[snake]
  const v = a !== undefined && a !== null ? a : b
  return bool(v)
}

function hasKey(o: Record<string, unknown>, camel: string, snake: string): boolean {
  return Object.prototype.hasOwnProperty.call(o, camel) || Object.prototype.hasOwnProperty.call(o, snake)
}

export function parseAffiliatePayoutBalance(raw: unknown): AffiliatePayoutBalance | null {
  const o = unwrapRaw(raw)
  if (!o) return null

  const minimumPayout = pickNum(o, "minimumPayout", "minimum_payout")
  const m = minimumPayout > 0 ? minimumPayout : 100

  const availableToRequest = pickNum(o, "availableToRequest", "available_to_request")

  const canRequestExplicit = hasKey(o, "canRequest", "can_request")
    ? pickBool(o, "canRequest", "can_request")
    : availableToRequest >= m

  const referralCountRaw = pickNum(o, "referralCount", "referral_count")
  const referralCount = Number.isFinite(referralCountRaw) ? Math.max(0, Math.floor(referralCountRaw)) : 0

  const perReferralRaw = pickNum(o, "perReferralEarnings", "per_referral_earnings")
  const perReferralEarnings =
    Number.isFinite(perReferralRaw) && perReferralRaw > 0
      ? perReferralRaw
      : AFFILIATE_PER_REFERRAL_EARNINGS

  return {
    referralCount,
    perReferralEarnings,
    totalEarnings: pickNum(o, "totalEarnings", "total_earnings"),
    totalPaid: pickNum(o, "totalPaid", "total_paid"),
    earningsSinceLastPayout: pickNum(o, "earningsSinceLastPayout", "earnings_since_last_payout"),
    pendingReserved: pickNum(o, "pendingReserved", "pending_reserved"),
    approvedReserved: pickNum(o, "approvedReserved", "approved_reserved"),
    availableToRequest,
    lastPaidAt:
      o.lastPaidAt != null
        ? String(o.lastPaidAt)
        : o.last_paid_at != null
          ? String(o.last_paid_at)
          : null,
    minimumPayout: m,
    canRequest: canRequestExplicit,
  }
}

export async function fetchAffiliatePayoutBalance(
  supabase: SupabaseClient,
  userId: string
): Promise<{ balance: AffiliatePayoutBalance | null; raw: unknown; error: Error | null }> {
  const { data, error } = await supabase.rpc("affiliate_payout_balance", {
    p_user_id: userId,
  })

  if (error) {
    return { balance: null, raw: null, error: new Error(error.message) }
  }

  return {
    balance: parseAffiliatePayoutBalance(data),
    raw: data,
    error: null,
  }
}
