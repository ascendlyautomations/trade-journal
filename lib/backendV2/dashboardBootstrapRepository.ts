/**
 * Dashboard bootstrap repositories (REST + RPC).
 * Flag OFF → production unchanged. Flag ON → one RPC seeds appDataCache.
 */

import type { SupabaseClient } from "@supabase/supabase-js"
import type { TableRow } from "@/lib/supabaseTypes"
import { mapProjectedRows } from "@/lib/supabaseProjectedQuery"
import {
  ACCOUNTS_SELECT,
  INITIAL_TRADES_LIMIT,
  seedAccountsCache,
  seedTradesCache,
} from "@/lib/appDataCache"
import { TRADES_APP_SELECT } from "@/lib/publicAccountPrivacy"
import { excludeBacktestTrades } from "@/lib/tradeModeFilters"
import type { DashboardBootstrapProviding } from "./adapters.ts"
import {
  decodeDashboardBootstrapV1,
  type DashboardBootstrapV1,
} from "./contracts.ts"
import {
  clearDashboardBootstrapCache,
  invalidateDashboardBootstrap,
  readDashboardBootstrapCache,
  writeDashboardBootstrapCache,
} from "./dashboardBootstrapCache.ts"
import {
  compareDashboardBootstraps,
  logDashboardBootstrapMismatches,
} from "./dashboardBootstrapCompare.ts"
import {
  beginDashboardBootstrapFlight,
  getDashboardBootstrapFlight,
} from "./dashboardBootstrapSingleFlight.ts"
import { isBackendV2Enabled } from "./flags.ts"
import {
  BackendV2RpcClient,
  createSupabaseBackendV2Transport,
} from "./rpcClient.ts"
import {
  measureAsync,
  recordBackendV2Telemetry,
  utf8ByteLength,
} from "./telemetry.ts"
import { BackendV2RpcNames } from "./versioning.ts"

const DASHBOARD_TRADE_LIMIT = 500

function asNum(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v
  if (v == null) return null
  const n = Number(v)
  return Number.isFinite(n) ? n : null
}

export class DashboardRestBootstrapRepository
  implements DashboardBootstrapProviding
{
  constructor(
    private readonly client: SupabaseClient,
    private readonly userId: string
  ) {}

  async loadDashboardBootstrap(input?: {
    accountId?: string | null
  }): Promise<DashboardBootstrapV1> {
    const uid = this.userId
    const accountId = input?.accountId?.trim() || null

    let accountsQuery = this.client
      .from("accounts")
      .select(ACCOUNTS_SELECT)
      .eq("user_id", uid)
    if (accountId) accountsQuery = accountsQuery.eq("id", accountId)

    let tradesQuery = this.client
      .from("trades")
      .select(TRADES_APP_SELECT)
      .eq("user_id", uid)
      .order("created_at", { ascending: false })
      .limit(DASHBOARD_TRADE_LIMIT)
    if (accountId) tradesQuery = tradesQuery.eq("account_id", accountId)

    const [accountsRes, tradesRes, countRes, payoutRes] = await Promise.all([
      accountsQuery.overrideTypes<
        DashboardBootstrapV1["data"]["accounts"],
        { merge: false }
      >(),
      tradesQuery.overrideTypes<TableRow<"trades">[], { merge: false }>(),
      this.client
        .from("trades")
        .select("id", { count: "exact", head: true })
        .eq("user_id", uid),
      this.client
        .from("account_payout_cycles")
        .select("payout_amount")
        .eq("user_id", uid),
    ])

    if (accountsRes.error) throw accountsRes.error
    if (tradesRes.error) throw tradesRes.error

    const accounts = accountsRes.data ?? []
    const trade_window = mapProjectedRows(
      tradesRes.data,
      (row) => row as TableRow<"trades">
    )
    const eligible = excludeBacktestTrades(
      trade_window as Array<{ mode?: string | null; account_type?: string | null }>
    )
    const total_trade_count = countRes.count ?? trade_window.length
    const history_complete =
      trade_window.length < DASHBOARD_TRADE_LIMIT ||
      trade_window.length >= total_trade_count

    const wins = eligible.filter((t) => Number((t as { pnl?: number }).pnl) > 0)
    const losses = eligible.filter((t) => Number((t as { pnl?: number }).pnl) < 0)
    const net = eligible.reduce(
      (s, t) => s + (Number((t as { pnl?: number }).pnl) || 0),
      0
    )

    let equity = 0
    const equity_points = [...eligible]
      .reverse()
      .map((t) => {
        equity += Number((t as { pnl?: number }).pnl) || 0
        return {
          t: String((t as { created_at?: string }).created_at ?? ""),
          v: equity,
        }
      })
      .filter((p) => p.t)

    const payout_total = (payoutRes.data ?? []).reduce(
      (s: number, r: { payout_amount?: number | null }) =>
        s + (Number(r.payout_amount) || 0),
      0
    )

    return {
      meta: {
        contract_version: "v1",
        server_time: new Date().toISOString(),
        viewer_id: uid,
      },
      data: {
        accounts,
        trade_window,
        trade_window_meta: {
          limit: DASHBOARD_TRADE_LIMIT,
          returned: trade_window.length,
          history_complete,
          total_trade_count,
          oldest_created_at: null,
          next_cursor: null,
        },
        metrics: {
          total_trades: eligible.length,
          wins: wins.length,
          losses: losses.length,
          win_rate: eligible.length ? wins.length / eligible.length : null,
          net_pnl: net,
          avg_rr: null,
          avg_win: null,
          avg_loss: null,
          biggest_win: null,
          biggest_loss: null,
        },
        equity_points,
        payout_total,
        recent_trades: trade_window.slice(0, 5),
      },
    }
  }
}

export class DashboardRpcBootstrapRepository
  implements DashboardBootstrapProviding
{
  private readonly client: BackendV2RpcClient

  constructor(supabase: SupabaseClient) {
    this.client = new BackendV2RpcClient({
      transport: createSupabaseBackendV2Transport(supabase),
    })
  }

  async loadDashboardBootstrap(input?: {
    accountId?: string | null
  }): Promise<DashboardBootstrapV1> {
    const args: Record<string, unknown> = {
      p_trade_limit: DASHBOARD_TRADE_LIMIT,
    }
    if (input?.accountId) args.p_account_id = input.accountId
    return this.client.callKnown(
      BackendV2RpcNames.dashboard,
      decodeDashboardBootstrapV1,
      {
        args,
        flagName: "backendV2.dashboard",
        cacheMiss: true,
      }
    )
  }
}

export type DashboardBootstrapLoadResult = {
  bootstrap: DashboardBootstrapV1
  source: "rpc" | "rest" | "cache"
  dualRunMismatches: number
  rpcRequestCount: number
  durationMs: number
  payloadBytes: number
  cacheHit: boolean
}

function seedAppCachesFromDashboard(
  userId: string,
  bootstrap: DashboardBootstrapV1
): void {
  const fetchedAt = Date.now()
  seedAccountsCache(userId, bootstrap.data.accounts as any[], fetchedAt)
  seedTradesCache(userId, bootstrap.data.trade_window as any[], fetchedAt, {
    historyComplete: Boolean(bootstrap.data.trade_window_meta.history_complete),
  })
}

/**
 * Sole application entry for Dashboard bootstrap (flag ON).
 * Exactly one network path: DashboardRpcBootstrapRepository.
 */
export async function loadDashboardBootstrapForUser(
  client: SupabaseClient,
  userId: string,
  options?: {
    force?: boolean
    accountId?: string | null
    caller?: string
  }
): Promise<DashboardBootstrapLoadResult> {
  const uid = userId.trim()
  if (!uid) throw new Error("loadDashboardBootstrapForUser requires userId")
  if (!isBackendV2Enabled("dashboard")) {
    throw new Error(
      "loadDashboardBootstrapForUser requires backendV2.dashboard flag ON"
    )
  }

  const caller = options?.caller ?? "unknown"
  if (options?.force) invalidateDashboardBootstrap(uid)

  if (!options?.force) {
    const cached = readDashboardBootstrapCache(uid)
    if (cached) {
      seedAppCachesFromDashboard(uid, cached)
      return {
        bootstrap: cached,
        source: "cache",
        dualRunMismatches: 0,
        rpcRequestCount: 0,
        durationMs: 0,
        payloadBytes: 0,
        cacheHit: true,
      }
    }
    const existing =
      getDashboardBootstrapFlight<DashboardBootstrapLoadResult>(uid)
    if (existing) return existing
  }

  return beginDashboardBootstrapFlight(uid, async () => {
    const cached = readDashboardBootstrapCache(uid)
    if (cached && !options?.force) {
      seedAppCachesFromDashboard(uid, cached)
      return {
        bootstrap: cached,
        source: "cache",
        dualRunMismatches: 0,
        rpcRequestCount: 0,
        durationMs: 0,
        payloadBytes: 0,
        cacheHit: true,
      }
    }

    if (process.env.NODE_ENV === "development") {
      console.debug("[backendV2.dashboard] RPC start", { userId: uid, caller })
    }

    const rpcRepo = new DashboardRpcBootstrapRepository(client)
    const restRepo = new DashboardRestBootstrapRepository(client, uid)

    const { value: rpc, ms } = await measureAsync(() =>
      rpcRepo.loadDashboardBootstrap({ accountId: options?.accountId })
    )

    let dualRunMismatches = 0
    const dualRun =
      process.env.NODE_ENV === "development" &&
      (process.env.NEXT_PUBLIC_BACKEND_V2_DUAL_RUN === "1" ||
        process.env.NEXT_PUBLIC_BACKEND_V2_DUAL_RUN === "true")
    if (dualRun) {
      try {
        const rest = await restRepo.loadDashboardBootstrap({
          accountId: options?.accountId,
        })
        const mismatches = compareDashboardBootstraps(rest, rpc)
        dualRunMismatches = mismatches.length
        logDashboardBootstrapMismatches(mismatches)
      } catch (err) {
        console.warn("[backendV2.dashboard] dual-run REST failed", err)
        dualRunMismatches = -1
      }
    }

    writeDashboardBootstrapCache(uid, rpc, "rpc")
    seedAppCachesFromDashboard(uid, rpc)

    let payloadBytes = 0
    try {
      payloadBytes = utf8ByteLength(JSON.stringify(rpc))
    } catch {
      payloadBytes = 0
    }

    recordBackendV2Telemetry({
      rpcName: BackendV2RpcNames.dashboard,
      success: true,
      executionMs: ms,
      decodeMs: null,
      payloadBytes,
      cacheHit: false,
      cacheMiss: true,
      errorCode: null,
      flagName: "backendV2.dashboard",
    })

    return {
      bootstrap: rpc,
      source: "rpc",
      dualRunMismatches,
      rpcRequestCount: 1,
      durationMs: ms,
      payloadBytes,
      cacheHit: false,
    }
  })
}

export {
  clearDashboardBootstrapCache,
  invalidateDashboardBootstrap,
  readDashboardBootstrapCache,
}
