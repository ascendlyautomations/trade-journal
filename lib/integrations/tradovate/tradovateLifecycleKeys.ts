import type { SupabaseClient } from "@supabase/supabase-js"
import type { TradovateImportPreviewTrade } from "./tradovateImportPreview.ts"

/** Lifecycles already on `trades` for this mapping at sync start (race-safe preview baseline). */
export async function loadTradovateLifecycleKeysAtSyncStart(
  supabase: SupabaseClient,
  params: { userId: string; mappingId: string }
): Promise<Set<string>> {
  const { data } = await supabase
    .from("trades")
    .select("broker_lifecycle_id")
    .eq("user_id", params.userId)
    .eq("import_source", "tradovate")
    .eq("broker_integration_account_id", params.mappingId)
    .not("broker_lifecycle_id", "is", null)

  const keys = new Set<string>()
  for (const row of data ?? []) {
    const key = String(row.broker_lifecycle_id ?? "").trim()
    if (key) keys.add(key)
  }
  return keys
}

export function filterPreviewsNotInBaseline(
  previews: TradovateImportPreviewTrade[],
  existingAtStart: Set<string>
): TradovateImportPreviewTrade[] {
  return previews.filter((p) => !existingAtStart.has(p.lifecycleKey))
}
