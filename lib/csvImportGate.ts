import type { SupabaseClient } from "@supabase/supabase-js"
import { isProActive } from "@/lib/subscription"
import { mirrorAccountSettingsHasUsedCsvImport } from "@/lib/profileSplitMirrorWrites"

export const FREE_PLAN_CSV_IMPORT_COOLDOWN_DAYS = 7
const MS_PER_DAY = 24 * 60 * 60 * 1000
export const FREE_PLAN_CSV_IMPORT_COOLDOWN_MS =
  FREE_PLAN_CSV_IMPORT_COOLDOWN_DAYS * MS_PER_DAY

export type CsvImportProfileGateFields = {
  is_pro?: boolean | null
  subscription_status?: string | null
  trial_end?: string | null
  last_csv_import_at?: string | null
}

export type CsvImportGateStatus =
  | { allowed: true }
  | { allowed: false; daysUntilNextImport: number }

export function evaluateCsvImportGate(
  profile: CsvImportProfileGateFields | null | undefined
): CsvImportGateStatus {
  if (isProActive(profile)) return { allowed: true }

  const lastAt = profile?.last_csv_import_at
  if (!lastAt) return { allowed: true }

  const last = new Date(lastAt)
  if (Number.isNaN(last.getTime())) return { allowed: true }

  const elapsed = Date.now() - last.getTime()
  if (elapsed >= FREE_PLAN_CSV_IMPORT_COOLDOWN_MS) return { allowed: true }

  const msRemaining = FREE_PLAN_CSV_IMPORT_COOLDOWN_MS - elapsed
  const daysUntilNextImport = Math.max(
    1,
    Math.ceil(msRemaining / MS_PER_DAY)
  )
  return { allowed: false, daysUntilNextImport }
}

export function csvImportLimitMessage(daysUntilNextImport?: number): string {
  const base =
    "Free members can import one CSV every 7 days. Upgrade to Pro for unlimited CSV imports."
  if (daysUntilNextImport == null) return base
  const dayLabel = daysUntilNextImport === 1 ? "day" : "days"
  return `${base}\n\nYour next free CSV import will be available in ${daysUntilNextImport} ${dayLabel}.`
}

export async function fetchCsvImportGateStatus(
  supabase: SupabaseClient,
  userId: string
): Promise<CsvImportGateStatus> {
  const { data: profile, error } = await supabase
    .from("profiles")
    .select("is_pro, subscription_status, trial_end, last_csv_import_at")
    .eq("id", userId)
    .maybeSingle()

  if (error) {
    console.error("[csvImportGate] profile fetch:", error)
    return { allowed: true }
  }

  return evaluateCsvImportGate(profile)
}

/** Free users may run one successful CSV import every 7 days until they upgrade to Pro. */
export async function assertCsvImportAllowedForFreePlan(
  supabase: SupabaseClient,
  userId: string
): Promise<{ ok: true } | { ok: false; daysUntilNextImport: number }> {
  const status = await fetchCsvImportGateStatus(supabase, userId)
  if (status.allowed) return { ok: true }
  return { ok: false, daysUntilNextImport: status.daysUntilNextImport }
}

export async function markProfileCsvImportUsed(
  supabase: SupabaseClient,
  userId: string
): Promise<{ error: Error | null }> {
  const now = new Date().toISOString()
  const { error } = await supabase
    .from("profiles")
    .update({ has_used_csv_import: true, last_csv_import_at: now })
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
