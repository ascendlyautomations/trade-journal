import type { SupabaseClient } from "@supabase/supabase-js"

export type AffiliatePayoutBalance = {
  totalEarnings: number
  earningsSinceLastPayout: number
  pendingReserved: number
  approvedReserved: number
  availableToRequest: number
  lastPaidAt: string | null
}

function num(v: unknown): number {
  if (v == null) return 0
  const n = Number(v)
  return Number.isFinite(n) ? n : 0
}

export function parseAffiliatePayoutBalance(raw: unknown): AffiliatePayoutBalance | null {
  if (raw == null || typeof raw !== "object") return null
  const o = raw as Record<string, unknown>
  return {
    totalEarnings: num(o.totalEarnings),
    earningsSinceLastPayout: num(o.earningsSinceLastPayout),
    pendingReserved: num(o.pendingReserved),
    approvedReserved: num(o.approvedReserved),
    availableToRequest: num(o.availableToRequest),
    lastPaidAt: o.lastPaidAt != null ? String(o.lastPaidAt) : null,
  }
}

export async function fetchAffiliatePayoutBalance(
  supabase: SupabaseClient,
  userId: string
): Promise<{ balance: AffiliatePayoutBalance | null; error: Error | null }> {
  const { data, error } = await supabase.rpc("affiliate_payout_balance", {
    p_user_id: userId,
  })

  if (error) {
    return { balance: null, error: new Error(error.message) }
  }

  return { balance: parseAffiliatePayoutBalance(data), error: null }
}
