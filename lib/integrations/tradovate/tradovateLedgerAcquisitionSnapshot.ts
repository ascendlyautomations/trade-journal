import type { SupabaseClient } from "@supabase/supabase-js"
import type { TradovateLedgerAcquisitionSnapshot } from "./tradovateHistoricalAcquisitionCore.ts"

export async function loadTradovateLedgerAcquisitionSnapshot(
  supabase: SupabaseClient,
  params: {
    userId: string
    mappingId: string
  }
): Promise<TradovateLedgerAcquisitionSnapshot> {
  const { data, error } = await supabase
    .from("broker_integration_executions")
    .select("external_fill_id, executed_at")
    .eq("user_id", params.userId)
    .eq("provider", "tradovate")
    .eq("broker_integration_account_id", params.mappingId)

  if (error || !data) {
    return {
      executionCount: 0,
      earliestExecutedAt: null,
      latestExecutedAt: null,
      fillIds: new Set(),
    }
  }

  let earliest: string | null = null
  let latest: string | null = null
  const fillIds = new Set<string>()
  for (const row of data) {
    const fillId = String(row.external_fill_id ?? "").trim()
    if (fillId) fillIds.add(fillId)
    const ts = row.executed_at ? String(row.executed_at) : null
    if (!ts) continue
    if (!earliest || ts < earliest) earliest = ts
    if (!latest || ts > latest) latest = ts
  }

  return {
    executionCount: data.length,
    earliestExecutedAt: earliest,
    latestExecutedAt: latest,
    fillIds,
  }
}

export async function loadTradovateIncrementalWatermark(
  supabase: SupabaseClient,
  mappingId: string
): Promise<string | null> {
  const { data } = await supabase
    .from("broker_integration_account_sync")
    .select("max_executed_at")
    .eq("broker_integration_account_id", mappingId)
    .maybeSingle()
  if (!data?.max_executed_at) return null
  return String(data.max_executed_at)
}
