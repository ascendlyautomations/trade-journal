import type { SupabaseClient } from "@supabase/supabase-js"
import { syncTradovateBrokerAccount } from "@/lib/integrations/tradovate/syncTradovateBrokerAccount"

export type LinkedTradovateImportTarget = {
  mappingId: string
  connectionId: string
  tradetraxsAccountName: string | null
  brokerAccountLabel: string | null
}

export type TradovateManualImportBatchResult = {
  ok: boolean
  results: {
    mappingId: string
    connectionId: string
    ok: boolean
    newTradeIds: string[]
    tradesCreated: number
    tradesUpdated: number
    newExecutions: number
    duplicateExecutions: number
    error?: string
  }[]
  newTradeIds: string[]
  totalTradesCreated: number
  totalTradesUpdated: number
}

export async function listLinkedTradovateImportTargets(
  supabase: SupabaseClient,
  userId: string
): Promise<LinkedTradovateImportTarget[]> {
  const { data: rows, error } = await supabase
    .from("broker_integration_accounts")
    .select(
      "id, connection_id, external_account_name, external_account_id, tradetraxs_account_id, sync_enabled, status, provider"
    )
    .eq("user_id", userId)
    .eq("provider", "tradovate")
    .not("tradetraxs_account_id", "is", null)

  if (error || !rows) return []

  const accountIds = [
    ...new Set(rows.map((r) => r.tradetraxs_account_id).filter(Boolean)),
  ] as string[]
  const nameById = new Map<string, string>()
  if (accountIds.length > 0) {
    const { data: accounts } = await supabase
      .from("accounts")
      .select("id, name")
      .eq("user_id", userId)
      .in("id", accountIds)
    for (const a of accounts ?? []) {
      nameById.set(String(a.id), String(a.name ?? ""))
    }
  }

  return rows
    .filter((r) => r.sync_enabled !== false && r.status !== "inactive")
    .map((r) => ({
      mappingId: String(r.id),
      connectionId: String(r.connection_id),
      tradetraxsAccountName: r.tradetraxs_account_id
        ? nameById.get(String(r.tradetraxs_account_id)) ?? null
        : null,
      brokerAccountLabel:
        (typeof r.external_account_name === "string" && r.external_account_name.trim()) ||
        String(r.external_account_id),
    }))
}

export async function runTradovateManualImportBatch(
  supabase: SupabaseClient,
  userId: string,
  targets: LinkedTradovateImportTarget[]
): Promise<TradovateManualImportBatchResult> {
  const results: TradovateManualImportBatchResult["results"] = []
  const newTradeIds: string[] = []
  let totalTradesCreated = 0
  let totalTradesUpdated = 0

  for (const target of targets) {
    const summary = await syncTradovateBrokerAccount(supabase, {
      userId,
      connectionId: target.connectionId,
      brokerIntegrationAccountId: target.mappingId,
      trigger: "manual",
    })
    const createdIds = summary.newTradeIds ?? []
    results.push({
      mappingId: target.mappingId,
      connectionId: target.connectionId,
      ok: summary.ok,
      newTradeIds: createdIds,
      tradesCreated: summary.tradesCreated,
      tradesUpdated: summary.tradesUpdated,
      newExecutions: summary.newExecutions,
      duplicateExecutions: summary.duplicateExecutions,
      error: summary.error,
    })
    if (summary.ok) {
      totalTradesCreated += summary.tradesCreated
      totalTradesUpdated += summary.tradesUpdated
      newTradeIds.push(...createdIds)
    }
  }

  return {
    ok: results.every((r) => r.ok),
    results,
    newTradeIds: [...new Set(newTradeIds)],
    totalTradesCreated,
    totalTradesUpdated,
  }
}
