import type { PostgrestError, SupabaseClient } from "@supabase/supabase-js"

import {
  formatPostgrestErrorMessage,
  isPostgrestRowCardinalityError,
  logPostgrestErrorDev,
} from "@/lib/postgrestError"
import { notifyAdminSubmission } from "@/lib/notifyAdminSubmission"
import { isRateLimitExceededError, formatRateLimitExceededMessage } from "@/lib/rateLimitErrors"
import { patchAffiliateApplicationCache } from "@/lib/affiliateDataRepository"

const MAX_INT4 = 2_147_483_647

/** Matches live `affiliate_applications` minimal schema. */
export const AFFILIATE_APPLICATION_SELECT_COLUMNS =
  [
    "id",
    "user_id",
    "social_handle",
    "followers",
    "requested_code",
    "status",
    "has_edited",
    "created_at",
    "reviewed_at",
    "reviewed_by",
  ].join(", ")

export type AffiliateApplicationRow = {
  id: string
  user_id: string
  social_handle: string | null
  followers: number | null
  requested_code: string | null
  status: string
  /** True after the user consumed their single edit while pending. */
  has_edited: boolean
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

/** Safe parse for DB/API rows; never throws. Missing id/user_id → null. */
function rowFromRaw(raw: Record<string, unknown>): AffiliateApplicationRow | null {
  try {
    const id = raw.id != null ? String(raw.id).trim() : ""
    const user_id = raw.user_id != null ? String(raw.user_id).trim() : ""
    if (!id || !user_id) return null

    const sh = raw.social_handle
    const rc = raw.requested_code

    return {
      id,
      user_id,
      social_handle:
        sh != null && String(sh).trim() !== "" ? String(sh) : null,
      followers: parseFollowersFromDb(raw.followers),
      requested_code:
        rc != null && String(rc).trim() !== "" ? String(rc) : null,
      status: String(raw.status ?? "pending"),
      has_edited: Boolean(raw.has_edited),
      created_at: raw.created_at != null ? String(raw.created_at) : null,
      reviewed_at: raw.reviewed_at != null ? String(raw.reviewed_at) : null,
      reviewed_by: raw.reviewed_by != null ? String(raw.reviewed_by) : null,
    }
  } catch {
    return null
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
  if (data == null || typeof data !== "object") return null

  return rowFromRaw(data as Record<string, unknown>)
}

/**
 * Latest **application** row (`affiliate_applications`), not `affiliates` (approved code / Stripe).
 * Never throws; returns null on error, empty, or unparseable row.
 */
export async function fetchLatestAffiliateApplication(
  supabase: SupabaseClient,
  userId: string,
  options?: { force?: boolean }
): Promise<AffiliateApplicationRow | null> {
  try {
    if (!userId?.trim()) {
      return null
    }

    const { ensureAffiliateApplicationLoaded } = await import(
      "./affiliateDataRepository.ts"
    )
    return ensureAffiliateApplicationLoaded(supabase, userId, options)
  } catch (e) {
    console.error("[Affiliate Fetch Error]", e)
    return null
  }
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

function notifyAffiliateApplicationSaved(data: unknown): void {
  if (data == null || typeof data !== "object") return
  const applicationId = rowFromRaw(data as Record<string, unknown>)?.id
  if (applicationId) {
    notifyAdminSubmission("affiliate_application", applicationId)
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
  const latest = await fetchLatestAffiliateApplication(supabase, userId, {
    force: true,
  })

  console.log("EXISTING (latest application row):", latest)

  if (latest?.status === "approved") {
    return { ok: false, error: "You are already approved as an affiliate." }
  }

  const payload = buildWritePayload(input)
  console.log("SUBMITTING (payload):", { ...payload, user_id: userId })

  if (latest?.status === "pending") {
    if (latest.has_edited) {
      return {
        ok: false,
        error: "You have already used your one edit while this application is pending.",
      }
    }

    const { data, error } = await supabase
      .from("affiliate_applications")
      .update({ ...payload, has_edited: true })
      .eq("id", latest.id)
      .select(AFFILIATE_APPLICATION_SELECT_COLUMNS)
      .maybeSingle()

    console.log("UPDATE RESULT:", { data, error })

    if (error) {
      logPostgrestErrorDev("submitAffiliateApplication update", error)
      console.error("UPDATE ERROR:", error)
      return { ok: false, error: formatPostgrestErrorMessage(error) }
    }

    if (!data) {
      console.error("UPDATE returned no row (0 rows updated or RLS blocked)", {
        applicationId: latest.id,
      })
      return {
        ok: false,
        error:
          "Could not save your application (nothing was updated). Check your connection or try again.",
      }
    }

    notifyAffiliateApplicationSaved(data)
    patchAffiliateApplicationCache(
      userId,
      mapSelectToApplicationRow("submitAffiliateApplication update", data, null)
    )
    return { ok: true, error: null }
  }

  const insertPayload = {
    ...payload,
    user_id: userId,
  }

  const { data, error } = await supabase
    .from("affiliate_applications")
    .insert(insertPayload)
    .select(AFFILIATE_APPLICATION_SELECT_COLUMNS)
    .maybeSingle()

  console.log("INSERT RESULT:", { data, error })

  if (error) {
    logPostgrestErrorDev("submitAffiliateApplication insert", error)
    console.error("INSERT ERROR:", error)
    if (isRateLimitExceededError(error.message)) {
      return {
        ok: false,
        error: formatRateLimitExceededMessage(
          "Too many affiliate applications this week. Try again later."
        ),
      }
    }
    return { ok: false, error: formatPostgrestErrorMessage(error) }
  }

  if (!data) {
    console.error("INSERT returned no row")
    return {
      ok: false,
      error: "Could not create your application. Try again.",
    }
  }

  notifyAffiliateApplicationSaved(data)

  patchAffiliateApplicationCache(
    userId,
    mapSelectToApplicationRow("submitAffiliateApplication insert", data, null)
  )

  return { ok: true, error: null }
}
