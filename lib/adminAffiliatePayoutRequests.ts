import type { SupabaseClient } from "@supabase/supabase-js"

import {
  AFFILIATE_PAYOUT_REQUEST_COLUMNS,
  type AffiliatePayoutRequestRow,
  type AffiliatePayoutStatus,
  parseAffiliatePayoutRequestRow,
} from "@/lib/affiliatePayoutRequests"
import { formatPostgrestErrorMessage } from "@/lib/postgrestError"

export type AffiliatePayoutStatusFilter = AffiliatePayoutStatus | "all"

export type AdminPayoutRequestRow = AffiliatePayoutRequestRow & {
  username: string | null
  name: string | null
  profile_referral_code: string | null
  referral_earnings: number | null
  affiliate_code: string | null
}

export type AdminPayoutStatusCounts = {
  pending: number
  approved: number
  paid: number
  rejected: number
  all: number
}

/** All requests, newest first. Optionally filter by status (not 'all'). */
export async function fetchAdminPayoutRequests(
  supabase: SupabaseClient,
  status: AffiliatePayoutStatusFilter
): Promise<{ rows: AdminPayoutRequestRow[]; error: Error | null }> {
  let q = supabase
    .from("affiliate_payout_requests")
    .select(AFFILIATE_PAYOUT_REQUEST_COLUMNS)
    .order("requested_at", { ascending: false })

  if (status !== "all") {
    q = q.eq("status", status)
  }

  const { data, error } = await q

  if (error) {
    return { rows: [], error: new Error(formatPostgrestErrorMessage(error)) }
  }

  const base = (data || []).map((r) => parseAffiliatePayoutRequestRow(r as Record<string, unknown>))
  const enriched = await enrichPayoutRows(supabase, base)
  return { rows: enriched, error: null }
}

async function enrichPayoutRows(
  supabase: SupabaseClient,
  rows: AffiliatePayoutRequestRow[]
): Promise<AdminPayoutRequestRow[]> {
  if (rows.length === 0) return []

  const userIds = [...new Set(rows.map((r) => r.user_id))]
  const affIds = [...new Set(rows.map((r) => r.affiliate_id).filter(Boolean))] as string[]

  let profs: unknown[] = []
  if (userIds.length > 0) {
    const { data } = await supabase
      .from("profiles")
      .select("id, username, name, referral_code, referral_earnings")
      .in("id", userIds)
    profs = data ?? []
  }

  let affs: { id: string; code: string | null }[] = []
  if (affIds.length > 0) {
    const { data: affData } = await supabase.from("affiliates").select("id, code").in("id", affIds)
    affs = (affData as { id: string; code: string | null }[]) ?? []
  }

  const profileById: Record<
    string,
    { username: string | null; name: string | null; referral_code: string | null; referral_earnings: number | null }
  > = {}
  for (const p of profs) {
    const o = p as Record<string, unknown>
    const id = String(o.id ?? "")
    profileById[id] = {
      username: o.username != null ? String(o.username) : null,
      name: o.name != null ? String(o.name) : null,
      referral_code: o.referral_code != null ? String(o.referral_code) : null,
      referral_earnings:
        o.referral_earnings != null && o.referral_earnings !== ""
          ? Number(o.referral_earnings)
          : null,
    }
  }

  const affCodeById: Record<string, string | null> = {}
  for (const a of affs || []) {
    const o = a as Record<string, unknown>
    affCodeById[String(o.id ?? "")] = o.code != null ? String(o.code) : null
  }

  return rows.map((r) => {
    const pr = profileById[r.user_id]
    const affCode = r.affiliate_id ? affCodeById[r.affiliate_id] ?? null : null
    return {
      ...r,
      username: pr?.username ?? null,
      name: pr?.name ?? null,
      profile_referral_code: pr?.referral_code ?? null,
      referral_earnings:
        pr?.referral_earnings != null && Number.isFinite(pr.referral_earnings)
          ? pr.referral_earnings
          : null,
      affiliate_code: affCode,
    }
  })
}

export async function fetchAdminPayoutStatusCounts(
  supabase: SupabaseClient
): Promise<{ counts: AdminPayoutStatusCounts | null; error: Error | null }> {
  const statuses = ["pending", "approved", "paid", "rejected"] as const
  const results = await Promise.all(
    statuses.map((s) =>
      supabase
        .from("affiliate_payout_requests")
        .select("*", { count: "exact", head: true })
        .eq("status", s)
    )
  )

  const allRes = await supabase
    .from("affiliate_payout_requests")
    .select("*", { count: "exact", head: true })

  const err = results.find((r) => r.error)?.error || allRes.error
  if (err) {
    return { counts: null, error: new Error(formatPostgrestErrorMessage(err)) }
  }

  return {
    counts: {
      pending: results[0].count ?? 0,
      approved: results[1].count ?? 0,
      paid: results[2].count ?? 0,
      rejected: results[3].count ?? 0,
      all: allRes.count ?? 0,
    },
    error: null,
  }
}
