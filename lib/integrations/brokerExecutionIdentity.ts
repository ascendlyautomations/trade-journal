import type { SupabaseClient } from "@supabase/supabase-js"
import type { BrokerIntegrationProvider } from "@/lib/integrations/brokerIntegrationConnection"

/** All broker account mapping rows for a stable provider external account id (incl. prior links). */
export async function listBrokerMappingIdsForExternalAccount(
  supabase: SupabaseClient,
  params: {
    userId: string
    provider: BrokerIntegrationProvider
    externalAccountId: string
  }
): Promise<string[]> {
  const { data, error } = await supabase
    .from("broker_integration_accounts")
    .select("id")
    .eq("user_id", params.userId)
    .eq("provider", params.provider)
    .eq("external_account_id", params.externalAccountId)

  if (error || !data) return []
  return data.map((row) => String(row.id))
}

/** Resolve canonical trade already linked to any of these provider fill ids for this user. */
export async function findCanonicalTradeIdForBrokerFillIds(
  supabase: SupabaseClient,
  params: {
    userId: string
    provider: BrokerIntegrationProvider
    fillIds: string[]
  }
): Promise<string | null> {
  if (params.fillIds.length === 0) return null

  const { data, error } = await supabase
    .from("broker_integration_executions")
    .select("canonical_trade_id")
    .eq("user_id", params.userId)
    .eq("provider", params.provider)
    .in("external_fill_id", params.fillIds)
    .not("canonical_trade_id", "is", null)
    .limit(1)

  if (error || !data?.length) return null
  const id = data[0]?.canonical_trade_id
  return id ? String(id) : null
}

/** Columns loaded for trade reconstruction (Tradovate + shared core). */
export const BROKER_EXECUTION_RECONSTRUCTION_SELECT =
  "external_fill_id, external_contract_id, side, quantity, price, executed_at" as const

/** Reconstruction columns plus Rithmic contract metadata from the execution ledger. */
export const BROKER_EXECUTION_RITHMIC_RECONSTRUCTION_SELECT =
  "external_fill_id, external_contract_id, side, quantity, price, executed_at, symbol_root, contract_name" as const

/** Projection of `broker_integration_executions` used by fill reconstruction. */
export type BrokerExecutionReconstructionRow = {
  external_fill_id: string
  external_contract_id: string
  side: string
  quantity: number | string
  price: number | string
  executed_at: string
}

export type BrokerExecutionRithmicReconstructionRow =
  BrokerExecutionReconstructionRow & {
    symbol_root: string | null
    contract_name: string | null
  }

type ListBrokerExecutionsBaseParams = {
  userId: string
  provider: BrokerIntegrationProvider
  externalAccountId: string
  fallbackMappingId?: string
}

function isBrokerExecutionReconstructionRow(
  row: unknown
): row is BrokerExecutionReconstructionRow {
  if (!row || typeof row !== "object") return false
  const o = row as Record<string, unknown>
  return (
    "external_fill_id" in o &&
    "external_contract_id" in o &&
    "side" in o &&
    "quantity" in o &&
    "price" in o &&
    "executed_at" in o
  )
}

function isBrokerExecutionRithmicReconstructionRow(
  row: unknown
): row is BrokerExecutionRithmicReconstructionRow {
  return (
    isBrokerExecutionReconstructionRow(row) &&
    "symbol_root" in row &&
    "contract_name" in row
  )
}

async function fetchBrokerExecutionsForExternalAccount(
  supabase: SupabaseClient,
  params: ListBrokerExecutionsBaseParams,
  select: string
): Promise<unknown[]> {
  const mappingIds = await listBrokerMappingIdsForExternalAccount(supabase, {
    userId: params.userId,
    provider: params.provider,
    externalAccountId: params.externalAccountId,
  })
  const scopeIds =
    mappingIds.length > 0
      ? mappingIds
      : params.fallbackMappingId
        ? [params.fallbackMappingId]
        : []

  if (scopeIds.length === 0) return []

  const { data, error } = await supabase
    .from("broker_integration_executions")
    .select(select)
    .eq("user_id", params.userId)
    .eq("provider", params.provider)
    .in("broker_integration_account_id", scopeIds)
    .order("executed_at", { ascending: true })
    .order("external_fill_id", { ascending: true })

  if (error || !data) return []
  return data
}

/** Ledger rows for one stable broker external account (all mapping rows, incl. prior connections). */
export async function listBrokerExecutionsForExternalAccount(
  supabase: SupabaseClient,
  params: ListBrokerExecutionsBaseParams & {
    select: typeof BROKER_EXECUTION_RECONSTRUCTION_SELECT
  }
): Promise<BrokerExecutionReconstructionRow[]>

export async function listBrokerExecutionsForExternalAccount(
  supabase: SupabaseClient,
  params: ListBrokerExecutionsBaseParams & {
    select: typeof BROKER_EXECUTION_RITHMIC_RECONSTRUCTION_SELECT
  }
): Promise<BrokerExecutionRithmicReconstructionRow[]>

export async function listBrokerExecutionsForExternalAccount(
  supabase: SupabaseClient,
  params: ListBrokerExecutionsBaseParams & {
    select:
      | typeof BROKER_EXECUTION_RECONSTRUCTION_SELECT
      | typeof BROKER_EXECUTION_RITHMIC_RECONSTRUCTION_SELECT
  }
): Promise<
  BrokerExecutionReconstructionRow[] | BrokerExecutionRithmicReconstructionRow[]
> {
  const rows = await fetchBrokerExecutionsForExternalAccount(
    supabase,
    params,
    params.select
  )
  if (params.select === BROKER_EXECUTION_RITHMIC_RECONSTRUCTION_SELECT) {
    return rows.filter(isBrokerExecutionRithmicReconstructionRow)
  }
  return rows.filter(isBrokerExecutionReconstructionRow)
}

export async function refreshBrokerExecutionRowAfterDuplicateInsert(
  supabase: SupabaseClient,
  params: {
    userId: string
    provider: BrokerIntegrationProvider
    externalFillId: string
    connectionId: string
    brokerIntegrationAccountId: string
  }
): Promise<void> {
  await supabase
    .from("broker_integration_executions")
    .update({
      connection_id: params.connectionId,
      broker_integration_account_id: params.brokerIntegrationAccountId,
      updated_at: new Date().toISOString(),
    })
    .eq("user_id", params.userId)
    .eq("provider", params.provider)
    .eq("external_fill_id", params.externalFillId)
}
