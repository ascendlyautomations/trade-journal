import type { SupabaseClient } from "@supabase/supabase-js"
import { loadActiveAppleSubscriptionForUser } from "./appleSubscription.ts"
import { entitlementEnforcementEnabled } from "./server/monetizationConfig.ts"
import { mirrorAccountSettingsHasUsedCsvImport } from "./profileSplitMirrorWrites.ts"
import {
  isTraxProActive,
  loadTraxProEntitlementSnapshot,
  type TraxProEntitlementProfile,
} from "./traxProEntitlement.ts"

export const FREE_PLAN_CSV_IMPORT_COOLDOWN_DAYS = 3
const MS_PER_DAY = 24 * 60 * 60 * 1000
export const FREE_PLAN_CSV_IMPORT_COOLDOWN_MS =
  FREE_PLAN_CSV_IMPORT_COOLDOWN_DAYS * MS_PER_DAY

export type CsvImportProfileGateFields = Pick<
  TraxProEntitlementProfile,
  "is_pro" | "creator_access" | "subscription_status" | "trial_end"
> & {
  last_csv_import_at?: string | null
}

export type CsvImportGateStatus =
  | { allowed: true }
  | { allowed: false; daysUntilNextImport: number }

export function evaluateCsvImportGate(
  profile: CsvImportProfileGateFields | null | undefined,
  traxProActive = false
): CsvImportGateStatus {
  if (traxProActive) return { allowed: true }

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

export function formatFreePlanCsvImportPricingLabel(
  days = FREE_PLAN_CSV_IMPORT_COOLDOWN_DAYS
): string {
  return `1 CSV import every ${days} days`
}

export const FREE_PLAN_CSV_IMPORT_PRICING_LABEL =
  formatFreePlanCsvImportPricingLabel()

export function csvImportLimitMessage(daysUntilNextImport?: number): string {
  const base = `Free members can import one CSV every ${FREE_PLAN_CSV_IMPORT_COOLDOWN_DAYS} days. Upgrade to Pro for unlimited CSV imports.`
  if (daysUntilNextImport == null) return base
  const dayLabel = daysUntilNextImport === 1 ? "day" : "days"
  return `${base}\n\nYour next free CSV import will be available in ${daysUntilNextImport} ${dayLabel}.`
}

export async function fetchCsvImportGateStatus(
  supabase: SupabaseClient,
  userId: string
): Promise<CsvImportGateStatus> {
  const enforced = await entitlementEnforcementEnabled(supabase)
  if (!enforced) return { allowed: true }

  const { data: profile, error } = await supabase
    .from("profiles")
    .select(
      "is_pro,creator_access,subscription_status,trial_end,early_access_enrolled_at,early_access_started_at,early_access_status,early_access_ends_at,early_access_campaign_id,early_access_enrollment_source,last_csv_import_at"
    )
    .eq("id", userId)
    .maybeSingle()

  if (error) {
    console.error("[csvImportGate] profile fetch:", error)
    return { allowed: true }
  }

  const loaded = await loadTraxProEntitlementSnapshot(supabase, userId)
  if (loaded.ok) {
    return evaluateCsvImportGate(profile, loaded.snapshot.traxProActive)
  }

  const appleSubscription = await loadActiveAppleSubscriptionForUser(
    supabase,
    userId
  )
  return evaluateCsvImportGate(profile, isTraxProActive(profile, appleSubscription))
}

/** Free users may run one successful CSV import every {@link FREE_PLAN_CSV_IMPORT_COOLDOWN_DAYS} days until they upgrade to Pro. */
export async function assertCsvImportAllowedForFreePlan(
  supabase: SupabaseClient,
  userId: string
): Promise<{ ok: true } | { ok: false; daysUntilNextImport: number }> {
  const status = await fetchCsvImportGateStatus(supabase, userId)
  if (status.allowed) return { ok: true }
  return { ok: false, daysUntilNextImport: status.daysUntilNextImport }
}

/** Call only after a CSV import persistence succeeds (failed/cancelled imports must not update). */
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
