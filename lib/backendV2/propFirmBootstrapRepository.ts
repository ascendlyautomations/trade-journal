import type { SupabaseClient } from "@supabase/supabase-js"
import type { Achievement } from "../achievementTypes.ts"
import {
  isFundedPropfirmAccount,
  type AccountPayoutCycle,
} from "../propfirmPayoutCycles.ts"
import type { PropfirmTrade } from "../propfirmMetrics.ts"
import {
  decodePropFirmBootstrapV1,
  type PropFirmBootstrapV1,
} from "./propFirmBootstrapContracts.ts"
import {
  invalidatePropFirmBootstrap,
  isPropFirmBootstrapCacheSoftStale,
  readPropFirmBootstrapCache,
  writePropFirmBootstrapCache,
} from "./propFirmBootstrapCache.ts"
import {
  beginPropFirmBootstrapFlight,
  getPropFirmBootstrapFlight,
} from "./propFirmBootstrapSingleFlight.ts"
import { isBackendV2Enabled } from "./flags.ts"
import {
  BackendV2RpcClient,
  BackendV2RpcError,
  createSupabaseBackendV2Transport,
} from "./rpcClient.ts"
import {
  isPropFirmRpcUnavailable,
  isPropFirmTransientError,
  logPropFirmRpcUnavailable,
} from "./propFirmRpcCompat.ts"
import {
  measureAsync,
  recordBackendV2Telemetry,
  utf8ByteLength,
} from "./telemetry.ts"
import { BackendV2RpcNames } from "./versioning.ts"

export type PropFirmBootstrapLoadResult = {
  bootstrap: PropFirmBootstrapV1
  source: "rpc" | "cache"
  rpcRequestCount: number
  durationMs: number
  payloadBytes: number
  cacheHit: boolean
}

export class PropFirmBootstrapStaleError extends Error {
  constructor() {
    super("prop_firm_bootstrap_stale")
    this.name = "PropFirmBootstrapStaleError"
  }
}

function mapPayoutCycleRow(row: Record<string, unknown>): AccountPayoutCycle {
  const drawdownBehavior = row.drawdown_behavior
  return {
    id: String(row.id ?? ""),
    account_id: String(row.account_id ?? ""),
    started_at: String(row.started_at ?? ""),
    ended_at: row.ended_at != null ? String(row.ended_at) : null,
    cycle_start_balance: Number(row.cycle_start_balance) || 0,
    payout_amount:
      row.payout_amount != null && row.payout_amount !== ""
        ? Number(row.payout_amount)
        : null,
    note: row.note != null ? String(row.note) : null,
    balance_before_payout:
      row.balance_before_payout != null && row.balance_before_payout !== ""
        ? Number(row.balance_before_payout)
        : null,
    balance_after_payout:
      row.balance_after_payout != null && row.balance_after_payout !== ""
        ? Number(row.balance_after_payout)
        : null,
    drawdown_behavior:
      drawdownBehavior === "reset_to_account" ||
      drawdownBehavior === "keep_trailing"
        ? drawdownBehavior
        : null,
    drawdown_floor_after_payout:
      row.drawdown_floor_after_payout != null &&
      row.drawdown_floor_after_payout !== ""
        ? Number(row.drawdown_floor_after_payout)
        : null,
    cycle_number:
      row.cycle_number != null && row.cycle_number !== ""
        ? Number(row.cycle_number)
        : null,
  }
}

export function groupPropFirmPayoutCyclesByAccountId(
  cycles: Record<string, unknown>[]
): Record<string, AccountPayoutCycle[]> {
  const grouped: Record<string, AccountPayoutCycle[]> = {}
  for (const row of cycles) {
    const mapped = mapPayoutCycleRow(row)
    const accountId = mapped.account_id
    if (!accountId) continue
    if (!grouped[accountId]) grouped[accountId] = []
    grouped[accountId].push(mapped)
  }
  for (const accountId of Object.keys(grouped)) {
    grouped[accountId]!.sort(
      (a, b) =>
        new Date(b.started_at).getTime() - new Date(a.started_at).getTime()
    )
  }
  return grouped
}

export function filterPropFirmBootstrapRowsByAccountIds<T extends { account_id?: unknown }>(
  rows: T[],
  accountIds: Array<string | number>
): T[] {
  const allowed = new Set(accountIds.map((id) => String(id).trim()).filter(Boolean))
  if (allowed.size === 0) return []
  return rows.filter((row) => allowed.has(String(row.account_id ?? "").trim()))
}

export type PropFirmBootstrapPageSnapshot = {
  accounts: Record<string, unknown>[]
  payoutCyclesByAccountId: Record<string, AccountPayoutCycle[]>
  achievements: Achievement[]
  trades: PropfirmTrade[]
}

export function snapshotPropFirmBootstrapPageData(
  bootstrap: PropFirmBootstrapV1,
  accountIds?: Array<string | number>
): PropFirmBootstrapPageSnapshot {
  const accounts = bootstrap.data.accounts
  const fundedIds = accounts
    .filter((account) => isFundedPropfirmAccount(account.mode))
    .map((account) => String(account.id))

  const payoutCyclesByAccountId = groupPropFirmPayoutCyclesByAccountId(
    bootstrap.data.payout_cycles.filter((cycle) =>
      fundedIds.includes(String(cycle.account_id ?? ""))
    )
  )

  const scopedAccountIds =
    accountIds && accountIds.length > 0
      ? accountIds
      : accounts.map((account) => String(account.id))

  const achievements = filterPropFirmBootstrapRowsByAccountIds(
    bootstrap.data.achievements as Achievement[],
    scopedAccountIds
  )
  const trades = filterPropFirmBootstrapRowsByAccountIds(
    bootstrap.data.trades as Array<PropfirmTrade & { account_id?: unknown }>,
    scopedAccountIds
  ) as PropfirmTrade[]

  return {
    accounts: accounts as Record<string, unknown>[],
    payoutCyclesByAccountId,
    achievements,
    trades,
  }
}

async function loadPropFirmBootstrapRpc(
  client: SupabaseClient
): Promise<PropFirmBootstrapV1> {
  const rpc = new BackendV2RpcClient({
    transport: createSupabaseBackendV2Transport(client),
  })
  return rpc.call(
    BackendV2RpcNames.propFirm,
    decodePropFirmBootstrapV1,
    {}
  )
}

export async function loadPropFirmBootstrapForUser(
  client: SupabaseClient,
  userId: string,
  options?: {
    force?: boolean
    caller?: string
    loadGeneration?: number
    expectedGeneration?: number
  }
): Promise<PropFirmBootstrapLoadResult> {
  if (!isBackendV2Enabled("propFirm")) {
    throw new BackendV2RpcError(
      "flag_off",
      "backendV2.propFirm is disabled",
      BackendV2RpcNames.propFirm
    )
  }

  const uid = userId.trim()
  if (!uid) {
    throw new BackendV2RpcError(
      "invalid_user",
      "userId required",
      BackendV2RpcNames.propFirm
    )
  }

  if (options?.force) invalidatePropFirmBootstrap(uid)

  if (!options?.force) {
    const cached = readPropFirmBootstrapCache(uid)
    if (cached) {
      if (
        options?.loadGeneration != null &&
        options.expectedGeneration != null &&
        options.loadGeneration !== options.expectedGeneration
      ) {
        throw new PropFirmBootstrapStaleError()
      }
      return {
        bootstrap: cached,
        source: "cache",
        rpcRequestCount: 0,
        durationMs: 0,
        payloadBytes: 0,
        cacheHit: true,
      }
    }
    const existing = getPropFirmBootstrapFlight<PropFirmBootstrapLoadResult>(uid)
    if (existing) return existing
  }

  return beginPropFirmBootstrapFlight(uid, async () => {
    const cached = readPropFirmBootstrapCache(uid)
    if (cached && !options?.force) {
      return {
        bootstrap: cached,
        source: "cache",
        rpcRequestCount: 0,
        durationMs: 0,
        payloadBytes: 0,
        cacheHit: true,
      }
    }

    try {
      const { value: bootstrap, ms } = await measureAsync(() =>
        loadPropFirmBootstrapRpc(client)
      )

      if (
        options?.loadGeneration != null &&
        options.expectedGeneration != null &&
        options.loadGeneration !== options.expectedGeneration
      ) {
        throw new PropFirmBootstrapStaleError()
      }

      writePropFirmBootstrapCache(uid, bootstrap, "rpc")

      let payloadBytes = 0
      try {
        payloadBytes = utf8ByteLength(JSON.stringify(bootstrap))
      } catch {
        payloadBytes = 0
      }

      recordBackendV2Telemetry({
        rpcName: BackendV2RpcNames.propFirm,
        success: true,
        executionMs: ms,
        decodeMs: null,
        payloadBytes,
        cacheHit: false,
        cacheMiss: true,
        errorCode: null,
        flagName: "backendV2.propFirm",
      })

      return {
        bootstrap,
        source: "rpc",
        rpcRequestCount: 1,
        durationMs: ms,
        payloadBytes,
        cacheHit: false,
      }
    } catch (err) {
      if (isPropFirmRpcUnavailable(err)) {
        logPropFirmRpcUnavailable(err)
        throw err
      }
      if (isPropFirmTransientError(err)) {
        throw err
      }
      throw err
    }
  })
}

export async function maybeRevalidatePropFirmBootstrap(
  client: SupabaseClient,
  userId: string
): Promise<void> {
  if (!isBackendV2Enabled("propFirm")) return
  if (!isPropFirmBootstrapCacheSoftStale(userId)) return
  try {
    await loadPropFirmBootstrapForUser(client, userId, {
      force: true,
      caller: "soft-stale-revalidate",
    })
  } catch (err) {
    if (isPropFirmRpcUnavailable(err) || isPropFirmTransientError(err)) return
    console.warn("[backendV2.propFirm] soft-stale revalidate failed", err)
  }
}
