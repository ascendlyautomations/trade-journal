import type { SupabaseClient } from "@supabase/supabase-js"
import {
  listSafeBrokerConnections,
  type BrokerIntegrationProvider,
} from "@/lib/integrations/brokerIntegrationConnection"
import type { TradovateDiscoveredAccount } from "@/lib/integrations/tradovate/tradovateAccountModels"
import { tradovateAccountSafeMetadata } from "@/lib/integrations/tradovate/tradovateAccountModels"

export type BrokerIntegrationAccountStatus = "discovered" | "linked" | "inactive"

/** Linked broker account mapping for Dashboard / session visibility (not import-capability filtered). */
export type LinkedBrokerAccountMappingView = {
  provider: BrokerIntegrationProvider
  mappingId: string
  connectionId: string
  tradetraxsAccountName: string | null
  brokerAccountLabel: string | null
}

export type SafeBrokerIntegrationAccountView = {
  id: string
  provider: BrokerIntegrationProvider
  externalAccountId: string
  externalAccountName: string | null
  externalDisplayName: string | null
  metadata: Record<string, unknown>
  tradetraxsAccountId: string | null
  tradetraxsAccountName: string | null
  syncEnabled: boolean
  status: BrokerIntegrationAccountStatus
  discoveredAt: string
  lastSeenAt: string
}

type MappingRow = {
  id: string
  provider: string
  external_account_id: string
  external_account_name: string | null
  external_display_name: string | null
  external_metadata: Record<string, unknown> | null
  tradetraxs_account_id: string | null
  sync_enabled: boolean
  status: string
  discovered_at: string
  last_seen_at: string
}

/** Fields applied when rediscovering a broker account row after disconnect/reconnect. */
export function brokerAccountFieldsAfterRediscovery(existing: {
  tradetraxs_account_id: string | null
  status: string
}): { status: BrokerIntegrationAccountStatus; syncEnabled: boolean } {
  if (existing.tradetraxs_account_id) {
    return { status: "linked", syncEnabled: true }
  }
  if (existing.status === "inactive") {
    return { status: "discovered", syncEnabled: false }
  }
  const status = existing.status as BrokerIntegrationAccountStatus
  return {
    status: status === "linked" ? "linked" : "discovered",
    syncEnabled: status === "linked",
  }
}

export async function findPriorBrokerAccountMappingForExternalId(
  supabase: SupabaseClient,
  params: {
    userId: string
    provider: BrokerIntegrationProvider
    externalAccountId: string
    excludeConnectionId: string
  }
): Promise<{ tradetraxs_account_id: string | null } | null> {
  const { data, error } = await supabase
    .from("broker_integration_accounts")
    .select("tradetraxs_account_id, updated_at")
    .eq("user_id", params.userId)
    .eq("provider", params.provider)
    .eq("external_account_id", params.externalAccountId)
    .neq("connection_id", params.excludeConnectionId)
    .order("updated_at", { ascending: false })
    .limit(20)

  if (error || !data?.length) return null
  const linked = data.find((row) => row.tradetraxs_account_id)
  if (linked) return { tradetraxs_account_id: String(linked.tradetraxs_account_id) }
  return { tradetraxs_account_id: null }
}

/** Re-enable links after explicit disconnect marked mappings inactive (credentials cleared). */
export async function reactivateBrokerAccountMappingsForConnection(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
  }
): Promise<void> {
  const now = new Date().toISOString()
  const { data: rows, error } = await supabase
    .from("broker_integration_accounts")
    .select("id, tradetraxs_account_id")
    .eq("user_id", params.userId)
    .eq("connection_id", params.connectionId)

  if (error || !rows?.length) return

  const linkedIds = rows.filter((r) => r.tradetraxs_account_id).map((r) => r.id)
  const discoveredIds = rows.filter((r) => !r.tradetraxs_account_id).map((r) => r.id)

  if (linkedIds.length > 0) {
    await supabase
      .from("broker_integration_accounts")
      .update({
        status: "linked",
        sync_enabled: true,
        updated_at: now,
      })
      .in("id", linkedIds)
      .eq("user_id", params.userId)
  }

  if (discoveredIds.length > 0) {
    await supabase
      .from("broker_integration_accounts")
      .update({
        status: "discovered",
        sync_enabled: false,
        updated_at: now,
      })
      .in("id", discoveredIds)
      .eq("user_id", params.userId)
  }
}

export async function upsertDiscoveredBrokerAccounts(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
    provider: BrokerIntegrationProvider
    discovered: TradovateDiscoveredAccount[]
  }
): Promise<void> {
  const now = new Date().toISOString()
  for (const account of params.discovered) {
    const { data: existing } = await supabase
      .from("broker_integration_accounts")
      .select("id, tradetraxs_account_id, status")
      .eq("connection_id", params.connectionId)
      .eq("provider", params.provider)
      .eq("external_account_id", account.externalAccountId)
      .maybeSingle()

    if (existing) {
      const continuity = brokerAccountFieldsAfterRediscovery(existing)
      const { error } = await supabase
        .from("broker_integration_accounts")
        .update({
          external_account_name: account.name,
          external_display_name: account.displayName,
          external_metadata: tradovateAccountSafeMetadata(account),
          last_seen_at: now,
          updated_at: now,
          status: continuity.status,
          sync_enabled: continuity.syncEnabled,
        })
        .eq("id", existing.id)
      if (error) throw new Error("broker_integration_accounts_update_failed")
      continue
    }

    const prior = await findPriorBrokerAccountMappingForExternalId(supabase, {
      userId: params.userId,
      provider: params.provider,
      externalAccountId: account.externalAccountId,
      excludeConnectionId: params.connectionId,
    })
    const inheritedTradetraxsId = prior?.tradetraxs_account_id ?? null
    const insertStatus: BrokerIntegrationAccountStatus = inheritedTradetraxsId
      ? "linked"
      : "discovered"

    const { error } = await supabase.from("broker_integration_accounts").insert({
      user_id: params.userId,
      connection_id: params.connectionId,
      provider: params.provider,
      external_account_id: account.externalAccountId,
      external_account_name: account.name,
      external_display_name: account.displayName,
      external_metadata: tradovateAccountSafeMetadata(account),
      tradetraxs_account_id: inheritedTradetraxsId,
      sync_enabled: Boolean(inheritedTradetraxsId),
      last_seen_at: now,
      updated_at: now,
      status: insertStatus,
    })
    if (error) throw new Error("broker_integration_accounts_insert_failed")
  }
}

export async function listSafeBrokerIntegrationAccounts(
  supabase: SupabaseClient,
  params: {
    userId: string
    provider: BrokerIntegrationProvider
    connectionId?: string
  }
): Promise<SafeBrokerIntegrationAccountView[]> {
  let query = supabase
    .from("broker_integration_accounts")
    .select(
      "id, provider, external_account_id, external_account_name, external_display_name, external_metadata, tradetraxs_account_id, sync_enabled, status, discovered_at, last_seen_at"
    )
    .eq("user_id", params.userId)
    .eq("provider", params.provider)

  if (params.connectionId) {
    query = query.eq("connection_id", params.connectionId)
  }

  const { data, error } = await query.order("external_account_name", { ascending: true })

  if (error) {
    throw new Error("broker_integration_accounts_list_failed")
  }

  const rows = (data ?? []) as MappingRow[]
  const linkedIds = [
    ...new Set(rows.map((r) => r.tradetraxs_account_id).filter(Boolean)),
  ] as string[]

  const nameByAccountId = new Map<string, string>()
  if (linkedIds.length > 0) {
    const { data: accountRows } = await supabase
      .from("accounts")
      .select("id, name")
      .eq("user_id", params.userId)
      .in("id", linkedIds)
    for (const row of accountRows ?? []) {
      nameByAccountId.set(String(row.id), String(row.name ?? ""))
    }
  }

  return rows.map((typed) => {
    const linkedName = typed.tradetraxs_account_id
      ? nameByAccountId.get(typed.tradetraxs_account_id) ?? null
      : null
    const status = typed.status as BrokerIntegrationAccountStatus
    return {
      id: typed.id,
      provider: params.provider,
      externalAccountId: typed.external_account_id,
      externalAccountName: typed.external_account_name,
      externalDisplayName: typed.external_display_name,
      metadata: typed.external_metadata ?? {},
      tradetraxsAccountId: typed.tradetraxs_account_id,
      tradetraxsAccountName: linkedName,
      syncEnabled: typed.sync_enabled,
      status: typed.tradetraxs_account_id ? "linked" : status === "inactive" ? "inactive" : status,
      discoveredAt: typed.discovered_at,
      lastSeenAt: typed.last_seen_at,
    }
  })
}

export async function linkBrokerIntegrationAccount(
  supabase: SupabaseClient,
  params: {
    userId: string
    provider: BrokerIntegrationProvider
    brokerAccountRowId: string
    tradetraxsAccountId: string
  }
): Promise<void> {
  const { data: mapping, error: mappingError } = await supabase
    .from("broker_integration_accounts")
    .select("id, user_id, provider")
    .eq("id", params.brokerAccountRowId)
    .eq("user_id", params.userId)
    .eq("provider", params.provider)
    .maybeSingle()

  if (mappingError || !mapping) {
    throw new Error("broker_account_not_found")
  }

  const { data: account, error: accountError } = await supabase
    .from("accounts")
    .select("id")
    .eq("id", params.tradetraxsAccountId)
    .eq("user_id", params.userId)
    .maybeSingle()

  if (accountError || !account) {
    throw new Error("tradetraxs_account_not_owned")
  }

  const { error } = await supabase
    .from("broker_integration_accounts")
    .update({
      tradetraxs_account_id: params.tradetraxsAccountId,
      status: "linked",
      sync_enabled: true,
      updated_at: new Date().toISOString(),
    })
    .eq("id", params.brokerAccountRowId)
    .eq("user_id", params.userId)

  if (error) {
    throw new Error("broker_account_link_failed")
  }
}

export async function disableBrokerAccountsForConnection(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
  }
): Promise<void> {
  await supabase
    .from("broker_integration_accounts")
    .update({
      sync_enabled: false,
      status: "inactive",
      updated_at: new Date().toISOString(),
    })
    .eq("user_id", params.userId)
    .eq("connection_id", params.connectionId)
}

/**
 * Authoritative linked broker accounts for UI visibility — matches Broker Integrations:
 * active connection + `tradetraxs_account_id` mapping. Does NOT filter on sync/import eligibility.
 */
export async function listLinkedBrokerAccountMappingsForUser(
  supabase: SupabaseClient,
  userId: string
): Promise<LinkedBrokerAccountMappingView[]> {
  const [tradovateConnections, rithmicConnections] = await Promise.all([
    listSafeBrokerConnections(supabase, { userId, provider: "tradovate" }),
    listSafeBrokerConnections(supabase, { userId, provider: "rithmic" }),
  ])
  const activeConnectionIds = new Set(
    [...tradovateConnections, ...rithmicConnections].map((c) => c.id)
  )
  if (activeConnectionIds.size === 0) return []

  const { data: rows, error } = await supabase
    .from("broker_integration_accounts")
    .select(
      "id, connection_id, provider, external_account_name, external_account_id, tradetraxs_account_id, status"
    )
    .eq("user_id", userId)
    .not("tradetraxs_account_id", "is", null)

  if (error || !rows) return []

  const linkedRows = rows.filter((r) => activeConnectionIds.has(String(r.connection_id)))

  const accountIds = [
    ...new Set(linkedRows.map((r) => r.tradetraxs_account_id).filter(Boolean)),
  ] as string[]
  const nameByAccountId = new Map<string, string>()
  if (accountIds.length > 0) {
    const { data: accountRows } = await supabase
      .from("accounts")
      .select("id, name")
      .eq("user_id", userId)
      .in("id", accountIds)
    for (const row of accountRows ?? []) {
      nameByAccountId.set(String(row.id), String(row.name ?? ""))
    }
  }

  return linkedRows.map((r) => {
    const provider = r.provider as BrokerIntegrationProvider
    const tradetraxsId = r.tradetraxs_account_id
      ? String(r.tradetraxs_account_id)
      : null
    return {
      provider,
      mappingId: String(r.id),
      connectionId: String(r.connection_id),
      tradetraxsAccountName: tradetraxsId
        ? nameByAccountId.get(tradetraxsId) ?? null
        : null,
      brokerAccountLabel:
        (typeof r.external_account_name === "string" &&
          r.external_account_name.trim()) ||
        String(r.external_account_id ?? ""),
    }
  })
}

export async function getBrokerIntegrationAccountMaxLastSeen(
  supabase: SupabaseClient,
  params: {
    userId: string
    provider: BrokerIntegrationProvider
    connectionId?: string
  }
): Promise<string | null> {
  let query = supabase
    .from("broker_integration_accounts")
    .select("last_seen_at")
    .eq("user_id", params.userId)
    .eq("provider", params.provider)

  if (params.connectionId) {
    query = query.eq("connection_id", params.connectionId)
  }

  const { data, error } = await query
    .order("last_seen_at", { ascending: false })
    .limit(1)
    .maybeSingle()

  if (error || !data) return null
  return data.last_seen_at
}
