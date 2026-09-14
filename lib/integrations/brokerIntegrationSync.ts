import type { SupabaseClient } from "@supabase/supabase-js"

export type BrokerAccountSyncView = {
  lastSyncAttemptAt: string | null
  lastSyncSuccessAt: string | null
  lastSyncStatus: string
  lastSyncErrorCode: string | null
}

const SYNC_LOCK_MS = 120_000

export async function loadBrokerAccountSyncViews(
  supabase: SupabaseClient,
  mappingIds: string[]
): Promise<Map<string, BrokerAccountSyncView>> {
  const out = new Map<string, BrokerAccountSyncView>()
  if (mappingIds.length === 0) return out

  const { data, error } = await supabase
    .from("broker_integration_account_sync")
    .select(
      "broker_integration_account_id, last_sync_attempt_at, last_sync_success_at, last_sync_status, last_sync_error_code"
    )
    .in("broker_integration_account_id", mappingIds)

  if (error || !data) return out

  for (const row of data) {
    out.set(String(row.broker_integration_account_id), {
      lastSyncAttemptAt: row.last_sync_attempt_at,
      lastSyncSuccessAt: row.last_sync_success_at,
      lastSyncStatus: row.last_sync_status ?? "never",
      lastSyncErrorCode: row.last_sync_error_code,
    })
  }
  return out
}

export async function tryAcquireBrokerSyncLock(
  supabase: SupabaseClient,
  params: {
    mappingId: string
    userId: string
    connectionId: string
  }
): Promise<boolean> {
  const now = new Date()
  const lockUntil = new Date(now.getTime() + SYNC_LOCK_MS).toISOString()
  const nowIso = now.toISOString()

  const { data: existing } = await supabase
    .from("broker_integration_account_sync")
    .select("broker_integration_account_id, sync_lock_until")
    .eq("broker_integration_account_id", params.mappingId)
    .maybeSingle()

  if (existing?.sync_lock_until) {
    const lockMs = new Date(existing.sync_lock_until).getTime()
    if (!Number.isNaN(lockMs) && lockMs > now.getTime()) {
      return false
    }
  }

  if (!existing) {
    const { error } = await supabase.from("broker_integration_account_sync").insert({
      broker_integration_account_id: params.mappingId,
      user_id: params.userId,
      connection_id: params.connectionId,
      last_sync_status: "syncing",
      last_sync_attempt_at: nowIso,
      sync_lock_until: lockUntil,
      updated_at: nowIso,
    })
    return !error
  }

  const { data: updated, error } = await supabase
    .from("broker_integration_account_sync")
    .update({
      last_sync_status: "syncing",
      last_sync_attempt_at: nowIso,
      sync_lock_until: lockUntil,
      updated_at: nowIso,
    })
    .eq("broker_integration_account_id", params.mappingId)
    .or(`sync_lock_until.is.null,sync_lock_until.lt."${nowIso}"`)
    .select("broker_integration_account_id")
    .maybeSingle()

  return !error && Boolean(updated)
}

export async function releaseBrokerSyncLock(
  supabase: SupabaseClient,
  mappingId: string,
  patch: {
    lastSyncStatus: string
    lastSyncSuccessAt?: string | null
    lastSyncErrorCode?: string | null
    lastSyncErrorMessage?: string | null
    maxExternalFillId?: number | null
    maxExecutedAt?: string | null
  }
): Promise<void> {
  const nowIso = new Date().toISOString()
  await supabase
    .from("broker_integration_account_sync")
    .update({
      last_sync_status: patch.lastSyncStatus,
      last_sync_success_at: patch.lastSyncSuccessAt ?? undefined,
      last_sync_error_code: patch.lastSyncErrorCode ?? null,
      last_sync_error_message: patch.lastSyncErrorMessage ?? null,
      max_external_fill_id: patch.maxExternalFillId ?? undefined,
      max_executed_at: patch.maxExecutedAt ?? undefined,
      sync_lock_until: null,
      updated_at: nowIso,
    })
    .eq("broker_integration_account_id", mappingId)
}
