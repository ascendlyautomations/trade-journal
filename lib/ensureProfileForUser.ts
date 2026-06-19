import type { SupabaseClient } from "@supabase/supabase-js"
import { REFERRAL_CODE_STORAGE_KEY } from "@/lib/referralPersistence"

export type EnsureProfileOptions = {
  userId: string
  /** Display name from signup form or OAuth user_metadata */
  name?: string | null
  /** Referral code from ?ref=, localStorage, or checkout body */
  referredBy?: string | null
}

export type EnsureProfileResult = {
  ok: boolean
  created: boolean
  error?: { message: string; code?: string }
}

export function generateProfileReferralCode(): string {
  return Math.random().toString(36).substring(2, 8).toUpperCase()
}

/** Client-only: read ?ref= code persisted during signup/OAuth redirect. */
export function readStoredReferralCode(): string | null {
  if (typeof window === "undefined") return null
  try {
    const raw = localStorage.getItem(REFERRAL_CODE_STORAGE_KEY)
    const trimmed = raw?.trim()
    return trimmed || null
  } catch {
    return null
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
 * Beta tester flags are applied by DB trigger on referred_by (e.g. TRAXBETA).
 */
export async function ensureProfileForUser(
  supabase: SupabaseClient,
  options: EnsureProfileOptions & {
    userMetadata?: Record<string, unknown> | null
  }
): Promise<EnsureProfileResult> {
  const { userId, referredBy, userMetadata } = options

  const { data: existing, error: selectErr } = await supabase
    .from("profiles")
    .select("id")
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
    return { ok: true, created: false }
  }

  const trimmedRef =
    referredBy != null ? String(referredBy).trim().toUpperCase() : ""
  const displayName = resolveDisplayName(options.name, userMetadata)

  const { error: insertErr } = await supabase.from("profiles").insert({
    id: userId,
    username: null,
    name: displayName,
    is_pro: false,
    subscription_status: "inactive",
    created_at: new Date().toISOString(),
    referral_code: generateProfileReferralCode(),
    referred_by: trimmedRef || null,
  })

  if (insertErr) {
    // Concurrent ensure or duplicate id — treat as existing profile.
    if (insertErr.code === "23505") {
      return { ok: true, created: false }
    }
    return {
      ok: false,
      created: false,
      error: { message: insertErr.message, code: insertErr.code },
    }
  }

  return { ok: true, created: true }
}
