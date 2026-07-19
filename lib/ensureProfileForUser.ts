import type { SupabaseClient } from "@supabase/supabase-js"
import { isBetaReferralRef } from "@/lib/betaReferralCode"
import { generateEarlyAccessReferralCode } from "@/lib/earlyAccess"
import {
  clearStoredReferralCode,
  readStoredReferralCode,
} from "@/lib/referralPersistence"

export { readStoredReferralCode, clearStoredReferralCode }

export type EnsureProfileOptions = {
  userId: string
  /** Display name from signup form or OAuth user_metadata */
  name?: string | null
  /** Referral code from ?ref=, localStorage, or checkout body */
  referredBy?: string | null
  /** Immutable origin used by privileged campaign enrollment checks. */
  signupFlowSource?: "standard_email" | "standard_oauth" | "creator" | null
}

export type EnsureProfileResult = {
  ok: boolean
  created: boolean
  error?: { message: string; code?: string }
}

export function generateProfileReferralCode(): string {
  return generateEarlyAccessReferralCode()
}

/**
 * Client-only, set-once repair of lost referral attribution. `referred_by`
 * is protected from authenticated self-updates, so the write happens on the
 * server (service role) and only when the column is currently NULL —
 * existing referral relationships are never overwritten.
 *
 * Clears browser referral storage only after a successful set-once write
 * (`attributed`) or when the profile already has `referred_by` (`already_set`).
 */
async function requestReferredByBackfill(
  supabase: SupabaseClient,
  referredBy: string
): Promise<void> {
  if (typeof window === "undefined") return
  try {
    const {
      data: { session },
    } = await supabase.auth.getSession()
    if (!session?.access_token) return
    const response = await fetch("/api/referral-attribution", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${session.access_token}`,
      },
      body: JSON.stringify({ code: referredBy }),
    })
    if (!response.ok) return
    const body = (await response.json().catch(() => null)) as {
      result?: string
    } | null
    if (body?.result === "attributed" || body?.result === "already_set") {
      clearStoredReferralCode()
    }
  } catch (err) {
    if (process.env.NODE_ENV !== "production") {
      console.error("ensureProfileForUser referred_by backfill:", err)
    }
  }
}

function resolveDisplayName(
  name: string | null | undefined,
  userMetadata?: Record<string, unknown> | null
): string | null {
  const direct = name != null ? String(name).trim() : ""
  if (direct) return direct

  if (!userMetadata) return null

  for (const key of ["full_name", "name"] as const) {
    const v = userMetadata[key]
    if (v != null && String(v).trim()) return String(v).trim()
  }

  return null
}

/**
 * Idempotent profile shell creation. Inserts only when no row exists for userId.
 * Never sets or overwrites username — NULL means "not chosen yet".
 * Beta enrollment is closed — beta invite codes are not stored as referred_by.
 */
export async function ensureProfileForUser(
  supabase: SupabaseClient,
  options: EnsureProfileOptions & {
    userMetadata?: Record<string, unknown> | null
  }
): Promise<EnsureProfileResult> {
  const { userId, referredBy, userMetadata } = options

  const trimmedRef =
    referredBy != null ? String(referredBy).trim().toUpperCase() : ""
  // Ignore closed beta invite codes so they cannot attribute or grant access.
  const resolvedReferredBy =
    trimmedRef && !isBetaReferralRef(trimmedRef) ? trimmedRef : null

  const { data: existing, error: selectErr } = await supabase
    .from("profiles")
    .select("id, referral_code, referred_by")
    .eq("id", userId)
    .maybeSingle()

  if (selectErr) {
    return {
      ok: false,
      created: false,
      error: { message: selectErr.message, code: selectErr.code },
    }
  }

  if (existing) {
    // Auth triggers may create the shell without a personal referral code.
    // referral_code is not a protected Early Access field, so backfill it here.
    if (
      existing.referral_code == null ||
      String(existing.referral_code).trim() === ""
    ) {
      const { error: referralErr } = await supabase
        .from("profiles")
        .update({ referral_code: generateProfileReferralCode() })
        .eq("id", userId)
      if (referralErr && process.env.NODE_ENV !== "production") {
        console.error("ensureProfileForUser referral backfill:", referralErr)
      }
    }

    const hasReferredBy =
      existing.referred_by != null &&
      String(existing.referred_by).trim() !== ""

    if (hasReferredBy) {
      // Profile already attributed — drop any leftover browser referral state
      // so a later login on this device cannot reuse it.
      clearStoredReferralCode()
    } else if (resolvedReferredBy) {
      // Shell was created without the incoming referral (auth trigger or a
      // concurrent ensure won the insert). Restore attribution set-once.
      await requestReferredByBackfill(supabase, resolvedReferredBy)
    }
    return { ok: true, created: false }
  }

  const displayName = resolveDisplayName(options.name, userMetadata)

  const { error: insertErr } = await supabase.from("profiles").insert({
    id: userId,
    username: null,
    name: displayName,
    is_pro: false,
    subscription_status: "inactive",
    created_at: new Date().toISOString(),
    referral_code: generateProfileReferralCode(),
    referred_by: resolvedReferredBy,
    signup_flow_source: options.signupFlowSource ?? null,
  })

  if (insertErr) {
    // Concurrent ensure or duplicate id — treat as existing profile. The
    // winning insert may not have carried the referral, so backfill set-once.
    if (insertErr.code === "23505") {
      if (resolvedReferredBy) {
        await requestReferredByBackfill(supabase, resolvedReferredBy)
      }
      return { ok: true, created: false }
    }
    return {
      ok: false,
      created: false,
      error: { message: insertErr.message, code: insertErr.code },
    }
  }

  // Referral was written on insert — clear browser state so it cannot
  // attribute a future account on this device.
  if (resolvedReferredBy) {
    clearStoredReferralCode()
  }

  return { ok: true, created: true }
}
