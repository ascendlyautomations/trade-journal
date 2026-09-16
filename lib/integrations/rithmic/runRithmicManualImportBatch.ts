import type { SupabaseClient } from "@supabase/supabase-js"
import { syncRithmicBrokerAccount } from "@/lib/integrations/rithmic/syncRithmicBrokerAccount"

export type LinkedRithmicImportTarget = {
  provider: "rithmic"
  mappingId: string
  connectionId: string
  tradetraxsAccountName: string | null
  brokerAccountLabel: string | null
}

export async function listLinkedRithmicImportTargets(
  supabase: SupabaseClient,
  userId: string
): Promise<LinkedRithmicImportTarget[]> {
  const { data: rows, error } = await supabase
    .from("broker_integration_accounts")
    .select(
      "id, connection_id, external_account_name, external_account_id, tradetraxs_account_id, sync_enabled, status, provider"
    )
    .eq("user_id", userId)
    .eq("provider", "rithmic")
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
      provider: "rithmic" as const,
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

export async function runRithmicManualImportBatch(
  supabase: SupabaseClient,
  userId: string,
  targets: LinkedRithmicImportTarget[],
  options?: { transientPassword?: string | null }
): Promise<{
  ok: boolean
  results: {
    provider: "rithmic"
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
}> {
  const results: {
    provider: "rithmic"
    mappingId: string
    connectionId: string
    ok: boolean
    newTradeIds: string[]
    tradesCreated: number
    tradesUpdated: number
    newExecutions: number
    duplicateExecutions: number
    error?: string
  }[] = []
  const newTradeIds: string[] = []
  let totalTradesCreated = 0
  let totalTradesUpdated = 0

  for (const target of targets) {
    const summary = await syncRithmicBrokerAccount(supabase, {
      userId,
      connectionId: target.connectionId,
      brokerIntegrationAccountId: target.mappingId,
      trigger: "manual",
      transientPassword: options?.transientPassword ?? null,
    })
    const createdIds = summary.newTradeIds ?? []
    results.push({
      provider: "rithmic",
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
