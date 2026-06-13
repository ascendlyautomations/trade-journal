import type { SupabaseClient } from "@supabase/supabase-js"
import { mirrorAccountSettingsHasUsedCsvImport } from "@/lib/profileSplitMirrorWrites"

/** Free users may run CSV import only once until they upgrade to Pro. */
export async function assertCsvImportAllowedForFreePlan(
  supabase: SupabaseClient,
  userId: string
): Promise<{ ok: true } | { ok: false }> {
  const { data: profile } = await supabase
    .from("profiles")
    .select("is_pro, has_used_csv_import")
    .eq("id", userId)
    .single()

  if (profile?.is_pro) return { ok: true }

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

  if (error) {
    return { error: new Error(error.message) }
  }

  const { error: mirrorErr } = await mirrorAccountSettingsHasUsedCsvImport(
    supabase,
    userId,
    true
  )
  if (mirrorErr) {
    console.error("mirror account_settings.has_used_csv_import:", mirrorErr)
  }

  return { error: null }
}
