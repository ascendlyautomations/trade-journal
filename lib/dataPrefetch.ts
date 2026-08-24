import type { SupabaseClient } from "@supabase/supabase-js"
import { isDemoUserId } from "./demo/constants"
import { seedDemoCaches } from "./demo/demoUser"
import { ensureAccountsLoaded, ensureTradesLoaded } from "./appDataCache"
import { scheduleDeferredWork } from "./scheduleDeferredWork"
import { ensureTradingAccountsSettingsLoaded } from "./tradingAccountsSettingsCache"
import { ensureNotificationPreferencesLoaded } from "./notificationPreferencesCache"
import { isBackendV2Enabled } from "./backendV2/flags.ts"

let warmedUserId: string | null = null
let criticalStartedUserId: string | null = null
let prefetchGeneration = 0

/**
 * CRITICAL PATH — start Dashboard-owned trades/accounts as soon as auth is known.
 * Runs in parallel with Session bootstrap (do not await Session first).
 */
export function startCriticalDashboardWarm(
  supabase: SupabaseClient,
  userId: string
): void {
  const id = userId.trim()
  if (!id || criticalStartedUserId === id) return
  criticalStartedUserId = id

  if (isDemoUserId(id)) {
    seedDemoCaches()
    return
  }

  void (async () => {
    if (isBackendV2Enabled("dashboard")) {
      const { loadDashboardBootstrapForUser } = await import(
        "./backendV2/dashboardBootstrapRepository.ts"
      )
      await loadDashboardBootstrapForUser(supabase, id, {
        caller: "startCriticalDashboardWarm",
      }).catch(() => null)
    } else {
      await Promise.all([
        ensureTradesLoaded(supabase, id).catch(() => []),
        ensureAccountsLoaded(supabase, id).catch(() => []),
      ])
    }
  })()
}

/**
 * Prefetch after auth.
 * - Critical Dashboard warm starts immediately (see startCriticalDashboardWarm).
 * - Secondary warmers (settings view / prefs when Session OFF) wait until idle.
 * - Achievements / Copy Trading are NOT warmed (lazy / domain-owned).
 */
export function warmAppDataCaches(
  supabase: SupabaseClient,
  userId: string
) {
  const id = userId.trim()
  if (!id || warmedUserId === id) return
  warmedUserId = id
  const generation = prefetchGeneration
  if (isDemoUserId(id)) {
    seedDemoCaches()
    return
  }

  // Bucket A — do not defer behind requestIdleCallback / 1s delay.
  startCriticalDashboardWarm(supabase, id)

  // Bucket B — after first paint / idle.
  // When Session + Dashboard ON, prefs + accounts are already owned — skip secondary warm.
  scheduleDeferredWork(() => {
    if (generation !== prefetchGeneration || warmedUserId !== id) return
    const sessionOn = isBackendV2Enabled("session")
    const dashboardOn = isBackendV2Enabled("dashboard")
    if (sessionOn && dashboardOn) return
    void Promise.all([
      ensureTradingAccountsSettingsLoaded(supabase, id).catch(() => []),
      sessionOn
        ? Promise.resolve(null)
        : ensureNotificationPreferencesLoaded(supabase, id).catch(() => null),
    ])
  }, 2000)
}

export function resetDataPrefetchSession() {
  prefetchGeneration += 1
  warmedUserId = null
  criticalStartedUserId = null
}
