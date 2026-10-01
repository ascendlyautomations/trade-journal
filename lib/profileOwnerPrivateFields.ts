import type { SupabaseClient } from "@supabase/supabase-js"

/** Owner-only profile columns. Direct SELECT is revoked from anon and authenticated. */
export type ProfileOwnerPrivateFields = {
  locked_account_id: string | null
  locked_account_name: string | null
  locked_account_number: string | null
  locked_account_size: string | null
  locked_account_type: string | null
  stripe_customer_id: string | null
  stripe_price_id: string | null
  referral_earnings: number | null
  billing_interval: string | null
}

function textOrNull(value: unknown): string | null {
  if (value == null || value === "") return null
  return String(value)
}

function numberOrNull(value: unknown): number | null {
  if (value == null || value === "") return null
  const n = typeof value === "number" ? value : Number(value)
  return Number.isFinite(n) ? n : null
}

export function parseProfileOwnerPrivateFields(
  raw: unknown
): ProfileOwnerPrivateFields | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null
  const row = raw as Record<string, unknown>
  return {
    locked_account_id: textOrNull(row.locked_account_id),
    locked_account_name: textOrNull(row.locked_account_name),
    locked_account_number: textOrNull(row.locked_account_number),
    locked_account_size: textOrNull(row.locked_account_size),
    locked_account_type: textOrNull(row.locked_account_type),
    stripe_customer_id: textOrNull(row.stripe_customer_id),
    stripe_price_id: textOrNull(row.stripe_price_id),
    referral_earnings: numberOrNull(row.referral_earnings),
    billing_interval: textOrNull(row.billing_interval),
  }
}

/** Returns the signed-in user's private profile fields. Strangers and guests get null. */
export async function fetchProfileOwnerPrivateFields(
  client: SupabaseClient
): Promise<ProfileOwnerPrivateFields | null> {
  const { data, error } = await client.rpc("profile_owner_private_fields")
  if (error) throw error
  return parseProfileOwnerPrivateFields(data)
}

/**
 * Attach owner-only columns onto a profile row for the signed-in user.
 * Rows for anyone else are left unchanged.
 */
export async function mergeOwnerPrivateProfileFields<T extends Record<string, unknown>>(
  client: SupabaseClient,
  row: T
): Promise<T> {
  const id = typeof row.id === "string" ? row.id : null
  if (!id) return row
  const { data: sessionData } = await client.auth.getSession()
  if (sessionData.session?.user.id !== id) return row
  const fields = await fetchProfileOwnerPrivateFields(client)
  if (!fields) return row
  return { ...row, ...fields }
}
