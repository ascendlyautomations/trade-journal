import type { SupabaseClient } from "@supabase/supabase-js"

export type AffiliateApplicationRow = {
  id: string
  user_id: string
  email: string | null
  full_name: string | null
  social_handle: string | null
  platform: string | null
  audience_size: string | null
  why_join: string | null
  promo_plan: string | null
  status: string
  requested_code: string | null
  approved_code: string | null
  admin_notes: string | null
  reviewed_by: string | null
  reviewed_at: string | null
  created_at: string | null
  updated_at: string | null
}

export type SubmitAffiliateApplicationInput = {
  email: string | null
  fullName: string | null
  socialHandle: string | null
  platform: string | null
  audienceSize: string | null
  whyJoin: string
  promoPlan: string | null
  requestedCode: string | null
}

function rowFromRaw(raw: Record<string, unknown>): AffiliateApplicationRow {
  return {
    id: String(raw.id ?? ""),
    user_id: String(raw.user_id ?? ""),
    email: raw.email != null ? String(raw.email) : null,
    full_name: raw.full_name != null ? String(raw.full_name) : null,
    social_handle: raw.social_handle != null ? String(raw.social_handle) : null,
    platform: raw.platform != null ? String(raw.platform) : null,
    audience_size: raw.audience_size != null ? String(raw.audience_size) : null,
    why_join: raw.why_join != null ? String(raw.why_join) : null,
    promo_plan: raw.promo_plan != null ? String(raw.promo_plan) : null,
    status: String(raw.status ?? "pending"),
    requested_code: raw.requested_code != null ? String(raw.requested_code) : null,
    approved_code: raw.approved_code != null ? String(raw.approved_code) : null,
    admin_notes: raw.admin_notes != null ? String(raw.admin_notes) : null,
    reviewed_by: raw.reviewed_by != null ? String(raw.reviewed_by) : null,
    reviewed_at: raw.reviewed_at != null ? String(raw.reviewed_at) : null,
    created_at: raw.created_at != null ? String(raw.created_at) : null,
    updated_at: raw.updated_at != null ? String(raw.updated_at) : null,
  }
}

/** Pending row for this user, if any. */
export async function fetchPendingAffiliateApplication(
  supabase: SupabaseClient,
  userId: string
): Promise<AffiliateApplicationRow | null> {
  const { data, error } = await supabase
    .from("affiliate_applications")
    .select("*")
    .eq("user_id", userId)
    .eq("status", "pending")
    .maybeSingle()

  if (error || !data) return null
  return rowFromRaw(data as Record<string, unknown>)
}

/** Most recent application (any status) for display when no pending. */
export async function fetchLatestAffiliateApplication(
  supabase: SupabaseClient,
  userId: string
): Promise<AffiliateApplicationRow | null> {
  const { data, error } = await supabase
    .from("affiliate_applications")
    .select("*")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle()

  if (error || !data) return null
  return rowFromRaw(data as Record<string, unknown>)
}

/**
 * Upsert a single pending application:
 * - If a pending row exists → update it.
 * - Else → insert new pending row (user may re-apply after rejection).
 */
export async function submitAffiliateApplication(
  supabase: SupabaseClient,
  userId: string,
  input: SubmitAffiliateApplicationInput
): Promise<{ ok: boolean; error: string | null }> {
  const payload = {
    user_id: userId,
    email: input.email,
    full_name: input.fullName?.trim() || null,
    social_handle: input.socialHandle?.trim() || null,
    platform: input.platform?.trim() || null,
    audience_size: input.audienceSize?.trim() || null,
    why_join: input.whyJoin.trim(),
    promo_plan: input.promoPlan?.trim() || null,
    requested_code: input.requestedCode?.trim().toUpperCase() || null,
    status: "pending" as const,
    updated_at: new Date().toISOString(),
  }

  const pending = await fetchPendingAffiliateApplication(supabase, userId)

  if (pending) {
    const { error } = await supabase.from("affiliate_applications").update(payload).eq("id", pending.id)
    if (error) return { ok: false, error: error.message }
    return { ok: true, error: null }
  }

  const insertPayload = {
    ...payload,
    created_at: new Date().toISOString(),
  }

  const { error } = await supabase.from("affiliate_applications").insert(insertPayload)
  if (error) return { ok: false, error: error.message }
  return { ok: true, error: null }
}
