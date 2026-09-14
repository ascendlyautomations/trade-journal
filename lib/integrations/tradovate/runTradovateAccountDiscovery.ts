import type { SupabaseClient } from "@supabase/supabase-js"
import {
  listSafeBrokerIntegrationAccounts,
  upsertDiscoveredBrokerAccounts,
} from "@/lib/integrations/brokerIntegrationAccounts"
import {
  normalizeTradovateAccountRow,
  type TradovateAccountListItemRaw,
} from "@/lib/integrations/tradovate/tradovateAccountModels"
import { fetchTradovateAccountListRaw, TradovateApiError } from "@/lib/integrations/tradovate/tradovateApiClient"

export const TRADOVATE_ACCOUNT_DISCOVERY_STALE_MS = 15 * 60 * 1000

export type TradovateAccountDiscoveryResult =
  | { ok: true; accountCount: number }
  | {
      ok: false
      reason: "not_connected" | "reconnect_required" | "provider_unavailable"
    }

export async function runTradovateAccountDiscovery(
  supabase: SupabaseClient,
  userId: string
): Promise<TradovateAccountDiscoveryResult> {
  const { data: connection, error } = await supabase
    .from("broker_integration_connections")
    .select("id, status")
    .eq("user_id", userId)
    .eq("provider", "tradovate")
    .maybeSingle()

  if (error || !connection || connection.status !== "connected") {
    return { ok: false, reason: "not_connected" }
  }

  try {
    const rawList = await fetchTradovateAccountListRaw(supabase, userId)
    const discovered = rawList
      .map((row) => normalizeTradovateAccountRow(row as TradovateAccountListItemRaw))
      .filter((row): row is NonNullable<typeof row> => row != null)

    await upsertDiscoveredBrokerAccounts(supabase, {
      userId,
      connectionId: connection.id,
      provider: "tradovate",
      discovered,
    })

    await supabase
      .from("broker_integration_connections")
      .update({ updated_at: new Date().toISOString() })
      .eq("id", connection.id)

    return { ok: true, accountCount: discovered.length }
  } catch (err) {
    if (err instanceof TradovateApiError) {
      if (err.code === "reconnect_required" || err.code === "unauthorized") {
        return { ok: false, reason: "reconnect_required" }
      }
      if (err.code === "not_connected") {
        return { ok: false, reason: "not_connected" }
      }
    }
    return { ok: false, reason: "provider_unavailable" }
  }
}

export function isTradovateDiscoveryStale(lastSeenAt: string | null): boolean {
  if (!lastSeenAt) return true
  const ms = new Date(lastSeenAt).getTime()
  if (Number.isNaN(ms)) return true
  return Date.now() - ms > TRADOVATE_ACCOUNT_DISCOVERY_STALE_MS
}

export async function loadTradovateAccountsForUser(
  supabase: SupabaseClient,
  userId: string,
  options?: { forceRefresh?: boolean }
): Promise<{
  connectionStatus: string
  discovery: TradovateAccountDiscoveryResult | null
  accounts: Awaited<ReturnType<typeof listSafeBrokerIntegrationAccounts>>
}> {
  const { data: connection } = await supabase
    .from("broker_integration_connections")
    .select("status")
    .eq("user_id", userId)
    .eq("provider", "tradovate")
    .maybeSingle()

  const connectionStatus = connection?.status ?? "disconnected"
  if (connectionStatus !== "connected") {
    return {
      connectionStatus,
      discovery: null,
      accounts: [],
    }
  }

  const { getBrokerIntegrationAccountMaxLastSeen } = await import(
    "@/lib/integrations/brokerIntegrationAccounts"
  )
  const lastSeen = await getBrokerIntegrationAccountMaxLastSeen(supabase, {
    userId,
    provider: "tradovate",
  })

  let discovery: TradovateAccountDiscoveryResult | null = null
  if (options?.forceRefresh || isTradovateDiscoveryStale(lastSeen)) {
    discovery = await runTradovateAccountDiscovery(supabase, userId)
  }

  const accounts = await listSafeBrokerIntegrationAccounts(supabase, {
    userId,
    provider: "tradovate",
  })

  return { connectionStatus, discovery, accounts }
}
