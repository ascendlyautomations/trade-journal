import type { PostgrestError, SupabaseClient } from "@supabase/supabase-js"

import { formatPostgrestErrorMessage } from "@/lib/postgrestError"

export type AffiliatePayoutStatus = "pending" | "approved" | "paid" | "rejected"

export type AffiliatePayoutRequestRow = {
  id: string
  user_id: string
  affiliate_id: string | null
  amount: number
  status: AffiliatePayoutStatus
  requested_at: string | null
  reviewed_at: string | null
  reviewed_by: string | null
  paid_at: string | null
  admin_notes: string | null
  payout_reference: string | null
  stripe_transfer_id: string | null
  created_at: string | null
  updated_at: string | null
}

export const AFFILIATE_PAYOUT_REQUEST_COLUMNS = [
  "id",
  "user_id",
  "affiliate_id",
  "amount",
  "status",
  "requested_at",
  "reviewed_at",
  "reviewed_by",
  "paid_at",
  "admin_notes",
  "payout_reference",
  "stripe_transfer_id",
  "created_at",
  "updated_at",
].join(", ")

export function parseAffiliatePayoutRequestRow(raw: Record<string, unknown>): AffiliatePayoutRequestRow {
  return {
    id: String(raw.id ?? ""),
    user_id: String(raw.user_id ?? ""),
    affiliate_id: raw.affiliate_id != null ? String(raw.affiliate_id) : null,
    amount: Number(raw.amount ?? 0),
    status: String(raw.status ?? "pending") as AffiliatePayoutStatus,
    requested_at: raw.requested_at != null ? String(raw.requested_at) : null,
    reviewed_at: raw.reviewed_at != null ? String(raw.reviewed_at) : null,
    reviewed_by: raw.reviewed_by != null ? String(raw.reviewed_by) : null,
    paid_at: raw.paid_at != null ? String(raw.paid_at) : null,
    admin_notes: raw.admin_notes != null ? String(raw.admin_notes) : null,
    payout_reference: raw.payout_reference != null ? String(raw.payout_reference) : null,
    stripe_transfer_id:
      raw.stripe_transfer_id != null ? String(raw.stripe_transfer_id) : null,
    created_at: raw.created_at != null ? String(raw.created_at) : null,
    updated_at: raw.updated_at != null ? String(raw.updated_at) : null,
  }
}

export async function fetchMyAffiliatePayoutRequests(
  supabase: SupabaseClient,
  userId: string
): Promise<{ rows: AffiliatePayoutRequestRow[]; error: Error | null }> {
  const { data, error } = await supabase
    .from("affiliate_payout_requests")
    .select(AFFILIATE_PAYOUT_REQUEST_COLUMNS)
    .eq("user_id", userId)
    .order("requested_at", { ascending: false })

  if (error) {
    return { rows: [], error: new Error(formatPostgrestErrorMessage(error)) }
  }

  const list = (data || []).map((r) => parseAffiliatePayoutRequestRow(r as Record<string, unknown>))
  return { rows: list, error: null }
}

export type InsertAffiliatePayoutRequestPayload = {
  user_id: string
  affiliate_id: string
  amount: number
  status: "pending"
}

export function mapAffiliatePayoutInsertError(error: PostgrestError): string {
  if (error.code === "23505") {
    return "You already have a pending payout request. Please wait until it is reviewed."
  }
  const m = `${error.message} ${error.details ?? ""}`.toLowerCase()
  if (m.includes("row-level security") || m.includes("policy")) {
    return "You must be an active affiliate to request a payout."
  }
  return formatPostgrestErrorMessage(error)
}

export async function insertAffiliatePayoutRequest(
  supabase: SupabaseClient,
  payload: InsertAffiliatePayoutRequestPayload
): Promise<{ error: Error | null }> {
  const { error } = await supabase.from("affiliate_payout_requests").insert({
    user_id: payload.user_id,
    affiliate_id: payload.affiliate_id,
    amount: payload.amount,
    status: payload.status,
  })

  if (error) {
    return { error: new Error(mapAffiliatePayoutInsertError(error)) }
  }
  return { error: null }
}
