import type { PostgrestError, SupabaseClient } from "@supabase/supabase-js"

import {
  formatPostgrestErrorMessage,
  isPostgrestRowCardinalityError,
  logPostgrestErrorDev,
} from "@/lib/postgrestError"

const MAX_INT4 = 2_147_483_647

/** Matches live `affiliate_applications` minimal schema. */
export const AFFILIATE_APPLICATION_SELECT_COLUMNS =
  ["id", "user_id", "social_handle", "followers", "requested_code", "status", "created_at", "reviewed_at", "reviewed_by"].join(
    ", "
  )

export type AffiliateApplicationRow = {
  id: string
  user_id: string
  social_handle: string | null
  followers: number | null
  requested_code: string | null
  status: string
  created_at: string | null
  reviewed_at: string | null
  reviewed_by: string | null
}

export type SubmitAffiliateApplicationInput = {
  socialHandle: string
  followers: number
  requestedCode: string | null
}

/** User-authored fields for insert/update (not status/review timestamps). */
type AffiliateApplicationWritePayload = {
  social_handle: string
  followers: number
  requested_code: string | null
  status: "pending"
}

function parseFollowersFromDb(v: unknown): number | null {
  if (v == null) return null
  if (typeof v === "number" && Number.isFinite(v)) return Math.trunc(Math.min(Math.max(v, 0), MAX_INT4))
  if (typeof v === "string" && v.trim() !== "") {
    const n = parseInt(v, 10)
    if (Number.isFinite(n)) return Math.min(Math.max(n, 0), MAX_INT4)
  }
  return null
}

function rowFromRaw(raw: Record<string, unknown>): AffiliateApplicationRow {
  return {
    id: String(raw.id ?? ""),
    user_id: String(raw.user_id ?? ""),
    social_handle: raw.social_handle != null ? String(raw.social_handle) : null,
    followers: parseFollowersFromDb(raw.followers),
    requested_code: raw.requested_code != null ? String(raw.requested_code) : null,
    status: String(raw.status ?? "pending"),
    created_at: raw.created_at != null ? String(raw.created_at) : null,
    reviewed_at: raw.reviewed_at != null ? String(raw.reviewed_at) : null,
    reviewed_by: raw.reviewed_by != null ? String(raw.reviewed_by) : null,
  }
}

function mapSelectToApplicationRow(
  context: string,
  data: unknown,
  error: PostgrestError | null
): AffiliateApplicationRow | null {
  if (error) {
    if (!isPostgrestRowCardinalityError(error)) {
      logPostgrestErrorDev(context, error)
    }
    return null
  }
  if (data == null) return null
  return rowFromRaw(data as Record<string, unknown>)
}

/**
 * Latest application row for this user (any status). No row → null (not an error).
 */
export async function fetchLatestAffiliateApplication(
  supabase: SupabaseClient,
  userId: string
): Promise<AffiliateApplicationRow | null> {
  const { data, error } = await supabase
    .from("affiliate_applications")
    .select(AFFILIATE_APPLICATION_SELECT_COLUMNS)
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle()

  return mapSelectToApplicationRow("fetchLatestAffiliateApplication", data, error)
}

function buildWritePayload(input: SubmitAffiliateApplicationInput): AffiliateApplicationWritePayload {
  const followers = Number.isFinite(input.followers)
    ? Math.min(Math.max(0, Math.floor(input.followers)), MAX_INT4)
    : 0
  const requested =
    input.requestedCode?.trim() !== ""
      ? input.requestedCode!.trim().toUpperCase()
      : null
  return {
    social_handle: input.socialHandle.trim(),
    followers,
    requested_code: requested,
    status: "pending",
  }
}

/**
 * Submit or update pending application only:
 * - update if latest row for user is pending
 * - insert otherwise (no row, rejected, etc.)
 */
export async function submitAffiliateApplication(
  supabase: SupabaseClient,
  userId: string,
  input: SubmitAffiliateApplicationInput
): Promise<{ ok: boolean; error: string | null }> {
  const latest = await fetchLatestAffiliateApplication(supabase, userId)

  if (latest?.status === "approved") {
    return { ok: false, error: "You are already approved as an affiliate." }
  }

  const payload = buildWritePayload(input)

  if (latest?.status === "pending") {
    const { error } = await supabase.from("affiliate_applications").update(payload).eq("id", latest.id)

    if (error) {
      logPostgrestErrorDev("submitAffiliateApplication update", error)
      return { ok: false, error: formatPostgrestErrorMessage(error) }
    }
    return { ok: true, error: null }
  }

  const insertPayload = {
    ...payload,
    user_id: userId,
  }

  const { error } = await supabase.from("affiliate_applications").insert(insertPayload)

  if (error) {
    logPostgrestErrorDev("submitAffiliateApplication insert", error)
    return { ok: false, error: formatPostgrestErrorMessage(error) }
  }
  return { ok: true, error: null }
}
