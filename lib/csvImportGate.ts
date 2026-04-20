import type { SupabaseClient } from "@supabase/supabase-js"
import { isProActive } from "@/lib/subscription"

/** Free users may run CSV import only once until they upgrade to Pro. */
export async function assertCsvImportAllowedForFreePlan(
  supabase: SupabaseClient,
  userId: string
): Promise<{ ok: true } | { ok: false }> {
  const { data: profile } = await supabase
    .from("profiles")
    .select("has_used_csv_import, is_pro, subscription_status")
    .eq("id", userId)
    .maybeSingle()

  if (isProActive(profile)) return { ok: true }

  if (profile?.has_used_csv_import === true) return { ok: false }

  return { ok: true }
}

export async function markProfileCsvImportUsed(
  supabase: SupabaseClient,
  userId: string
): Promise<{ error: Error | null }> {
  const { error } = await supabase
    .from("profiles")
    .update({ has_used_csv_import: true })
    .eq("id", userId)

  return { error: error ? new Error(error.message) : null }
}
