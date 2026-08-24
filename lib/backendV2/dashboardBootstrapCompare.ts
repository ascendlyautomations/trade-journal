import type { DashboardBootstrapV1 } from "./contracts.ts"

export type DashboardBootstrapMismatch = {
  path: string
  rest: unknown
  rpc: unknown
}

function idsOf(rows: Array<Record<string, unknown> | { id?: string }>): string[] {
  return rows
    .map((r) => String((r as { id?: string }).id ?? ""))
    .filter(Boolean)
    .sort()
}

/** Lightweight dual-run compare — ids + key metrics, not full row equality. */
export function compareDashboardBootstraps(
  rest: DashboardBootstrapV1,
  rpc: DashboardBootstrapV1
): DashboardBootstrapMismatch[] {
  const mismatches: DashboardBootstrapMismatch[] = []

  const restAccounts = idsOf(rest.data.accounts as Array<{ id?: string }>)
  const rpcAccounts = idsOf(rpc.data.accounts as Array<{ id?: string }>)
  if (JSON.stringify(restAccounts) !== JSON.stringify(rpcAccounts)) {
    mismatches.push({
      path: "accounts.ids",
      rest: restAccounts,
      rpc: rpcAccounts,
    })
  }

  const restTrades = idsOf(rest.data.trade_window)
  const rpcTrades = idsOf(rpc.data.trade_window)
  if (JSON.stringify(restTrades) !== JSON.stringify(rpcTrades)) {
    mismatches.push({
      path: "trade_window.ids",
      rest: restTrades.slice(0, 20),
      rpc: rpcTrades.slice(0, 20),
    })
  }

  if (
    rest.data.trade_window_meta.history_complete !==
    rpc.data.trade_window_meta.history_complete
  ) {
    mismatches.push({
      path: "trade_window_meta.history_complete",
      rest: rest.data.trade_window_meta.history_complete,
      rpc: rpc.data.trade_window_meta.history_complete,
    })
  }

  const metricKeys = ["total_trades", "net_pnl", "win_rate"] as const
  for (const key of metricKeys) {
    const a = rest.data.metrics[key]
    const b = rpc.data.metrics[key]
    if (a == null && b == null) continue
    if (Number(a) !== Number(b)) {
      mismatches.push({ path: `metrics.${key}`, rest: a, rpc: b })
    }
  }

  return mismatches
}

export function logDashboardBootstrapMismatches(
  mismatches: DashboardBootstrapMismatch[]
): void {
  if (!mismatches.length) {
    console.info("[backendV2.dashboard] dual-run OK — no mismatches")
    return
  }
  console.warn("[backendV2.dashboard] dual-run mismatches", mismatches)
}
