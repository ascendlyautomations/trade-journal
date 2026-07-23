import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"
import { hapticSuccess } from "@/lib/nativeHaptics"

/** Normalize creator invite codes for lookup (trim + uppercase). */
export function normalizeCreatorAccessCode(raw: string | null | undefined): string {
  return String(raw ?? "")
    .trim()
    .toUpperCase()
}

const CREATOR_FLOW_CODE_KEY = "tt_creator_access_code"

/** Persist invite code across signup → onboarding → redeem. */
export function enterCreatorFlow(code: string): void {
  if (typeof window === "undefined") return
  const normalized = normalizeCreatorAccessCode(code)
  if (!normalized) return
  try {
    sessionStorage.setItem(CREATOR_FLOW_CODE_KEY, normalized)
  } catch {
    /* ignore */
  }
}

export function getPendingCreatorCode(): string | null {
  if (typeof window === "undefined") return null
  try {
    const raw = sessionStorage.getItem(CREATOR_FLOW_CODE_KEY)
    const normalized = normalizeCreatorAccessCode(raw)
    return normalized || null
  } catch {
    return null
  }
}

export function isCreatorFlowActive(): boolean {
  return getPendingCreatorCode() != null
}

export function clearCreatorFlow(): void {
  if (typeof window === "undefined") return
  try {
    sessionStorage.removeItem(CREATOR_FLOW_CODE_KEY)
  } catch {
    /* ignore */
  }
}

/** Redeem path — preserves the invite code in the URL. */
export function buildCreatorRedeemPath(code: string): string {
  const normalized = normalizeCreatorAccessCode(code)
  return `/creator?code=${encodeURIComponent(normalized)}`
}

/**
 * Dedicated Creator Access signup (not the trial/billing login page).
 * Used when an unauthenticated visitor opens /creator?code=XXXX.
 */
export function buildCreatorSignupPath(code: string): string {
  const normalized = normalizeCreatorAccessCode(code)
  return `/creator/signup?code=${encodeURIComponent(normalized)}`
}

/** @deprecated Prefer {@link buildCreatorSignupPath}. */
export function buildCreatorLoginNextPath(code: string): string {
  return buildCreatorSignupPath(code)
}

export const CREATOR_ACCESS_SUCCESS_MESSAGE =
  "🎉 Complimentary Pro access has been activated. Enjoy exploring TradeTraxs!"

export const CREATOR_ACCESS_INVALID_MESSAGE =
  "This creator access code is invalid or has expired."

export type CreatorEntitlement = {
  creator_access: true
  creator_code: string
  creator_granted_at: string
  is_pro: true
}

export type RedeemCreatorResult =
  | { ok: true; alreadyGranted: boolean; entitlement: CreatorEntitlement }
  | {
      ok: false
      invalid: boolean
      status: number
      error: string
      message: string
      result?: string | null
    }

/** Call the creator redeem API for the current session. */
const redeemInFlight = new Map<string, Promise<RedeemCreatorResult>>()

export async function redeemCreatorAccessCode(
  code: string
): Promise<RedeemCreatorResult> {
  const normalized = normalizeCreatorAccessCode(code)
  if (!normalized) {
    return {
      ok: false,
      invalid: true,
      status: 400,
      error: "invalid_code",
      message: CREATOR_ACCESS_INVALID_MESSAGE,
    }
  }

  const existing = redeemInFlight.get(normalized)
  if (existing) return existing

  const promise = redeemCreatorAccessCodeOnce(normalized).finally(() => {
    redeemInFlight.delete(normalized)
  })
  redeemInFlight.set(normalized, promise)
  return promise
}

async function redeemCreatorAccessCodeOnce(
  normalized: string
): Promise<RedeemCreatorResult> {
  try {
    const res = await fetch("/api/creator/redeem", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(await supabaseBearerHeaders()),
      },
      body: JSON.stringify({ code: normalized }),
    })

    const payload = (await res.json().catch(() => null)) as {
      ok?: boolean
      alreadyGranted?: boolean
      error?: string
      message?: string
      result?: string
      entitlement?: CreatorEntitlement
    } | null

    if (!res.ok || !payload?.ok) {
      const message =
        payload?.message ||
        payload?.error ||
        `Creator redeem failed (${res.status})`
      return {
        ok: false,
        invalid: payload?.error === "invalid_code",
        status: res.status,
        error: payload?.error || "redeem_failed",
        message,
        result: payload?.result ?? null,
      }
    }

    const entitlement: CreatorEntitlement = payload.entitlement ?? {
      creator_access: true,
      creator_code: normalized,
      creator_granted_at: new Date().toISOString(),
      is_pro: true,
    }

    hapticSuccess("creator-redeem")
    return {
      ok: true,
      alreadyGranted: payload.alreadyGranted === true,
      entitlement,
    }
  } catch (err) {
    return {
      ok: false,
      invalid: false,
      status: 0,
      error: "network_error",
      message: err instanceof Error ? err.message : "Network error during redeem",
    }
  }
}
