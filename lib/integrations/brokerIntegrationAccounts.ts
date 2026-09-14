import type { SupabaseClient } from "@supabase/supabase-js"
import type { BrokerIntegrationProvider } from "@/lib/integrations/brokerIntegrationConnection"
import type { TradovateDiscoveredAccount } from "@/lib/integrations/tradovate/tradovateAccountModels"
import { tradovateAccountSafeMetadata } from "@/lib/integrations/tradovate/tradovateAccountModels"

export type BrokerIntegrationAccountStatus = "discovered" | "linked" | "inactive"

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
      const { error } = await supabase
        .from("broker_integration_accounts")
        .update({
          external_account_name: account.name,
          external_display_name: account.displayName,
          external_metadata: tradovateAccountSafeMetadata(account),
          last_seen_at: now,
          updated_at: now,
          status: existing.tradetraxs_account_id ? "linked" : existing.status,
        })
        .eq("id", existing.id)
      if (error) throw new Error("broker_integration_accounts_update_failed")
      continue
    }

    const { error } = await supabase.from("broker_integration_accounts").insert({
      user_id: params.userId,
      connection_id: params.connectionId,
      provider: params.provider,
      external_account_id: account.externalAccountId,
      external_account_name: account.name,
      external_display_name: account.displayName,
      external_metadata: tradovateAccountSafeMetadata(account),
      last_seen_at: now,
      updated_at: now,
      status: "discovered",
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
