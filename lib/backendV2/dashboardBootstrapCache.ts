/**
 * Canonical Dashboard Bootstrap cache (Symbol.for / globalThis).
 * Realtime patches here later — never re-run bootstrap for incremental updates.
 */

import type { DashboardBootstrapV1 } from "./contracts.ts"
import { clearDashboardBootstrapFlights } from "./dashboardBootstrapSingleFlight.ts"

type Entry = {
  userId: string
  bootstrap: DashboardBootstrapV1
  fetchedAt: number
  source: "rpc" | "rest" | "cache"
}

type CacheStore = {
  entry: Entry | null
  listeners: Set<() => void>
}

const GLOBAL_KEY = Symbol.for("tradetraxs.dashboardBootstrap.cache")

function store(): CacheStore {
  const g = globalThis as typeof globalThis & {
    [GLOBAL_KEY]?: CacheStore
  }
  if (!g[GLOBAL_KEY]) {
    g[GLOBAL_KEY] = { entry: null, listeners: new Set() }
  }
  return g[GLOBAL_KEY]
}

function notifyDashboardBootstrapListeners() {
  for (const listener of store().listeners) listener()
}

export function subscribeDashboardBootstrapCache(listener: () => void): () => void {
  store().listeners.add(listener)
  return () => store().listeners.delete(listener)
}

export function readDashboardBootstrapCache(
  userId: string | null | undefined
): DashboardBootstrapV1 | null {
  const entry = store().entry
  if (!userId || !entry || entry.userId !== userId) return null
  return entry.bootstrap
}

export function writeDashboardBootstrapCache(
  userId: string,
  bootstrap: DashboardBootstrapV1,
  source: Entry["source"] = "rpc"
): void {
  store().entry = { userId, bootstrap, fetchedAt: Date.now(), source }
  notifyDashboardBootstrapListeners()
}

export function clearDashboardBootstrapCache(): void {
  store().entry = null
  clearDashboardBootstrapFlights()
  notifyDashboardBootstrapListeners()
}

export function invalidateDashboardBootstrap(userId?: string | null): void {
  if (userId) {
    const entry = store().entry
    if (entry?.userId === userId) {
      store().entry = null
      notifyDashboardBootstrapListeners()
    }
    clearDashboardBootstrapFlights(userId)
    return
  }
  clearDashboardBootstrapCache()
}
