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

/** Ledger rows for one stable broker external account (all mapping rows, incl. prior connections). */
export async function listBrokerExecutionsForExternalAccount<
  T extends string,
>(
  supabase: SupabaseClient,
  params: {
    userId: string
    provider: BrokerIntegrationProvider
    externalAccountId: string
    select: T
    fallbackMappingId?: string
  }
): Promise<Record<T, unknown>[]> {
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
    .select(params.select)
    .eq("user_id", params.userId)
    .eq("provider", params.provider)
    .in("broker_integration_account_id", scopeIds)
    .order("executed_at", { ascending: true })
    .order("external_fill_id", { ascending: true })

  if (error || !data) return []
  return data as Record<T, unknown>[]
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
