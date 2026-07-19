import type { SupabaseClient } from "@supabase/supabase-js"
import { isBetaReferralRef } from "./betaReferralCode.ts"

/**
 * Server-side, set-once backfill of `profiles.referred_by`.
 *
 * Fixes the signup race where an auth trigger (or a concurrent ensure call)
 * creates the profile shell before the client insert that carries the
 * referral attribution, leaving `referred_by` permanently NULL because the
 * column is protected from authenticated self-updates.
 *
 * Guarantees:
 * - `referred_by` is only ever written when it is currently NULL
 *   (conditional UPDATE — the predicate is re-checked under the row lock,
 *   so concurrent calls cannot double-write or overwrite).
 * - Existing referral relationships are never modified.
 * - Self-referrals, the closed beta code, and codes owned by no profile
 *   are rejected.
 */

/** Alphanumeric only — also prevents ILIKE wildcard injection. */
const REFERRAL_ATTRIBUTION_CODE_PATTERN = /^[A-Z0-9]{4,20}$/

export function normalizeReferralAttributionCode(
  raw: unknown
): string | null {
  if (raw == null) return null
  const code = String(raw).trim().toUpperCase()
  if (!code) return null
  if (isBetaReferralRef(code)) return null
  if (!REFERRAL_ATTRIBUTION_CODE_PATTERN.test(code)) return null
  return code
}

export type ReferredByBackfillResult =
  | "attributed"
  | "already_set"
  | "invalid_code"
  | "no_code"
  | "profile_missing"
  | "error"

export type ReferralAttributionProfile = {
  id: string
  referral_code: string | null
  referred_by: string | null
}

/** Minimal persistence port so the set-once logic is unit-testable. */
export type ReferralAttributionDb = {
  loadProfile(
    userId: string
  ): Promise<ReferralAttributionProfile | null | "error">
  /** Number of OTHER profiles owning `code` (case-insensitive). */
  countCodeOwners(code: string, excludeUserId: string): Promise<number | "error">
  /**
   * UPDATE profiles SET referred_by = code
   * WHERE id = userId AND referred_by IS NULL.
   * Returns true only when a row was actually updated.
   */
  setReferredByIfNull(userId: string, code: string): Promise<boolean | "error">
}

export async function backfillReferredByIfMissing(
  db: ReferralAttributionDb,
  userId: string,
  rawCode: unknown
): Promise<ReferredByBackfillResult> {
  const code = normalizeReferralAttributionCode(rawCode)
  if (!code) return "no_code"

  const profile = await db.loadProfile(userId)
  if (profile === "error") return "error"
  if (!profile) return "profile_missing"

  if (
    profile.referred_by != null &&
    String(profile.referred_by).trim() !== ""
  ) {
    return "already_set"
  }

  if (normalizeReferralAttributionCode(profile.referral_code) === code) {
    return "invalid_code"
  }

  const owners = await db.countCodeOwners(code, userId)
  if (owners === "error") return "error"
  if (owners < 1) return "invalid_code"

  const updated = await db.setReferredByIfNull(userId, code)
  if (updated === "error") return "error"
  // Lost the write race to a concurrent attribution — the earlier one wins.
  return updated ? "attributed" : "already_set"
}

/** Adapter for API routes (pass the service-role client). */
export function createSupabaseReferralAttributionDb(
  client: SupabaseClient
): ReferralAttributionDb {
  return {
    async loadProfile(userId) {
      const { data, error } = await client
        .from("profiles")
        .select("id, referral_code, referred_by")
        .eq("id", userId)
        .maybeSingle()
      if (error) return "error"
      if (!data) return null
      return {
        id: String(data.id),
        referral_code:
          data.referral_code != null ? String(data.referral_code) : null,
        referred_by:
          data.referred_by != null ? String(data.referred_by) : null,
      }
    },
    async countCodeOwners(code, excludeUserId) {
      const { count, error } = await client
        .from("profiles")
        .select("id", { count: "exact", head: true })
        .ilike("referral_code", code)
        .neq("id", excludeUserId)
      if (error) return "error"
      return count ?? 0
    },
    async setReferredByIfNull(userId, code) {
      const { data, error } = await client
        .from("profiles")
        .update({ referred_by: code })
        .eq("id", userId)
        .is("referred_by", null)
        .select("id")
      if (error) return "error"
      return Array.isArray(data) && data.length > 0
    },
  }
}
