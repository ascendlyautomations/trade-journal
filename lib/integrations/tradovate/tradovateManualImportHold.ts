import type { SupabaseClient } from "@supabase/supabase-js"

const HOLD_MS = 30 * 60 * 1000

export type TradovateProviderSyncState = {
  manualImportHoldUntil?: string
  manualImportPreviewLifecycleKeys?: string[]
}

export function readTradovateProviderSyncState(
  raw: Record<string, unknown> | null | undefined
): TradovateProviderSyncState {
  if (!raw || typeof raw !== "object") return {}
  const holdUntil =
    typeof raw.manualImportHoldUntil === "string"
      ? raw.manualImportHoldUntil
      : undefined
  const keys = Array.isArray(raw.manualImportPreviewLifecycleKeys)
    ? raw.manualImportPreviewLifecycleKeys.filter(
        (k): k is string => typeof k === "string" && k.trim().length > 0
      )
    : undefined
  return {
    manualImportHoldUntil: holdUntil,
    manualImportPreviewLifecycleKeys: keys,
  }
}

export function isManualImportHoldActive(
  state: TradovateProviderSyncState,
  nowMs: number = Date.now()
): boolean {
  const until = state.manualImportHoldUntil
  if (!until) return false
  const ms = new Date(until).getTime()
  return Number.isFinite(ms) && ms > nowMs
}

export async function loadTradovateProviderSyncState(
  supabase: SupabaseClient,
  mappingId: string
): Promise<TradovateProviderSyncState> {
  const { data } = await supabase
    .from("broker_integration_account_sync")
    .select("provider_sync_state")
    .eq("broker_integration_account_id", mappingId)
    .maybeSingle()
  return readTradovateProviderSyncState(
    (data?.provider_sync_state as Record<string, unknown> | null) ?? null
  )
}

export async function setManualImportPreviewHold(
  supabase: SupabaseClient,
  mappingId: string,
  lifecycleKeys: string[]
): Promise<void> {
  const existing = await loadTradovateProviderSyncState(supabase, mappingId)
  const holdUntil = new Date(Date.now() + HOLD_MS).toISOString()
  const merged: TradovateProviderSyncState = {
    ...existing,
    manualImportHoldUntil: holdUntil,
    manualImportPreviewLifecycleKeys: lifecycleKeys,
  }
  await supabase
    .from("broker_integration_account_sync")
    .update({
      provider_sync_state: merged,
      updated_at: new Date().toISOString(),
    })
    .eq("broker_integration_account_id", mappingId)
}

export async function clearManualImportPreviewHold(
  supabase: SupabaseClient,
  mappingId: string
): Promise<void> {
  const existing = await loadTradovateProviderSyncState(supabase, mappingId)
  const merged: TradovateProviderSyncState = { ...existing }
  delete merged.manualImportHoldUntil
  delete merged.manualImportPreviewLifecycleKeys
  await supabase
    .from("broker_integration_account_sync")
    .update({
      provider_sync_state: merged,
      updated_at: new Date().toISOString(),
    })
    .eq("broker_integration_account_id", mappingId)
}
