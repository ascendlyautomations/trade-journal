import type { SupabaseClient } from "@supabase/supabase-js"
import { mirrorAccountSettingsHasUsedCsvImport } from "./profileSplitMirrorWrites.ts"

export type CsvImportGateStatus = { allowed: true }

/** CSV import is included on the Free plan — no subscription cooldown. */
export function evaluateCsvImportGate(): CsvImportGateStatus {
  return { allowed: true }
}

export const FREE_PLAN_CSV_IMPORT_PRICING_LABEL = "Unlimited CSV imports"

export function csvImportLimitMessage(_daysUntilNextImport?: number): string {
  return "CSV import is included on the Free plan."
}

export async function fetchCsvImportGateStatus(
  _supabase: SupabaseClient,
  _userId: string
): Promise<CsvImportGateStatus> {
  return { allowed: true }
}

export async function assertCsvImportAllowedForFreePlan(
  _supabase: SupabaseClient,
  _userId: string
): Promise<{ ok: true }> {
  return { ok: true }
}

/** Optional analytics mirror after a successful CSV import (does not gate access). */
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
