import type { SupabaseClient } from "@supabase/supabase-js"
import { loadOwnedBrokerConnection } from "@/lib/integrations/brokerConnectionAccess"

export type BrokerConnectionPendingLinkView = {
  tradetraxsAccountId: string
  tradetraxsAccountName: string | null
}

export async function countBrokerAccountsOnConnection(
  supabase: SupabaseClient,
  params: { userId: string; connectionId: string }
): Promise<number> {
  const { count, error } = await supabase
    .from("broker_integration_accounts")
    .select("id", { count: "exact", head: true })
    .eq("user_id", params.userId)
    .eq("connection_id", params.connectionId)
    .neq("status", "inactive")
    .is("tradetraxs_account_id", null)

  if (error) throw new Error("broker_integration_accounts_count_failed")
  return count ?? 0
}

export async function loadBrokerConnectionPendingLink(
  supabase: SupabaseClient,
  params: { userId: string; connectionId: string }
): Promise<BrokerConnectionPendingLinkView | null> {
  const { data, error } = await supabase
    .from("broker_integration_connections")
    .select("pending_tradetraxs_account_id")
    .eq("id", params.connectionId)
    .eq("user_id", params.userId)
    .maybeSingle()

  if (error || !data?.pending_tradetraxs_account_id) return null

  const tradetraxsAccountId = String(data.pending_tradetraxs_account_id)
  const { data: account } = await supabase
    .from("accounts")
    .select("id, name")
    .eq("id", tradetraxsAccountId)
    .eq("user_id", params.userId)
    .maybeSingle()

  if (!account) {
    await clearBrokerConnectionPendingLink(supabase, params)
    return null
  }

  return {
    tradetraxsAccountId,
    tradetraxsAccountName: account.name?.trim() || null,
  }
}

export async function setBrokerConnectionPendingLink(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
    tradetraxsAccountId: string
  }
): Promise<BrokerConnectionPendingLinkView> {
  const owned = await loadOwnedBrokerConnection(supabase, {
    userId: params.userId,
    connectionId: params.connectionId,
    provider: "tradovate",
  })
  if (!owned || owned.status !== "connected") {
    throw new Error("broker_connection_not_connected")
  }

  const discoveredCount = await countBrokerAccountsOnConnection(supabase, {
    userId: params.userId,
    connectionId: params.connectionId,
  })
  if (discoveredCount > 0) {
    throw new Error("broker_accounts_already_discovered")
  }

  const { data: account, error: accountError } = await supabase
    .from("accounts")
    .select("id, name")
    .eq("id", params.tradetraxsAccountId)
    .eq("user_id", params.userId)
    .maybeSingle()

  if (accountError || !account) {
    throw new Error("tradetraxs_account_not_owned")
  }

  const { error } = await supabase
    .from("broker_integration_connections")
    .update({
      pending_tradetraxs_account_id: params.tradetraxsAccountId,
      updated_at: new Date().toISOString(),
    })
    .eq("id", params.connectionId)
    .eq("user_id", params.userId)

  if (error) throw new Error("broker_pending_link_set_failed")

  return {
    tradetraxsAccountId: String(account.id),
    tradetraxsAccountName: account.name?.trim() || null,
  }
}

export async function clearBrokerConnectionPendingLink(
  supabase: SupabaseClient,
  params: { userId: string; connectionId: string }
): Promise<void> {
  const { error } = await supabase
    .from("broker_integration_connections")
    .update({
      pending_tradetraxs_account_id: null,
      updated_at: new Date().toISOString(),
    })
    .eq("id", params.connectionId)
    .eq("user_id", params.userId)

  if (error) throw new Error("broker_pending_link_clear_failed")
}