import type { SupabaseClient } from "@supabase/supabase-js"
import { loadOwnedBrokerConnection } from "@/lib/integrations/brokerConnectionAccess"
import {
  getBrokerIntegrationAccountMaxLastSeen,
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
  userId: string,
  connectionId: string
): Promise<TradovateAccountDiscoveryResult> {
  const owned = await loadOwnedBrokerConnection(supabase, {
    userId,
    connectionId,
    provider: "tradovate",
  })

  if (!owned || owned.status !== "connected") {
    return { ok: false, reason: "not_connected" }
  }

  try {
    const rawList = await fetchTradovateAccountListRaw(supabase, userId, connectionId)
    const discovered = rawList
      .map((row) => normalizeTradovateAccountRow(row as TradovateAccountListItemRaw))
      .filter((row): row is NonNullable<typeof row> => row != null)

    await upsertDiscoveredBrokerAccounts(supabase, {
      userId,
      connectionId,
      provider: "tradovate",
      discovered,
    })

    await supabase
      .from("broker_integration_connections")
      .update({ updated_at: new Date().toISOString() })
      .eq("id", connectionId)
      .eq("user_id", userId)

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

export async function loadTradovateConnectionAccounts(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string,
  options?: { forceRefresh?: boolean }
): Promise<{
  connectionStatus: string
  discovery: TradovateAccountDiscoveryResult | null
  accounts: Awaited<ReturnType<typeof listSafeBrokerIntegrationAccounts>>
}> {
  const owned = await loadOwnedBrokerConnection(supabase, {
    userId,
    connectionId,
    provider: "tradovate",
  })

  const connectionStatus = owned?.status ?? "disconnected"
  if (connectionStatus !== "connected") {
    return {
      connectionStatus,
      discovery: null,
      accounts: [],
    }
  }

  const lastSeen = await getBrokerIntegrationAccountMaxLastSeen(supabase, {
    userId,
    provider: "tradovate",
    connectionId,
  })

  let discovery: TradovateAccountDiscoveryResult | null = null
  if (options?.forceRefresh || isTradovateDiscoveryStale(lastSeen)) {
    discovery = await runTradovateAccountDiscovery(supabase, userId, connectionId)
  }

  const accounts = await listSafeBrokerIntegrationAccounts(supabase, {
    userId,
    provider: "tradovate",
    connectionId,
  })

  return { connectionStatus, discovery, accounts }
}
