import type { SupabaseClient } from "@supabase/supabase-js"
import { isDemoUserId } from "./demo/constants"
import { seedDemoCaches } from "./demo/demoUser"
import { ensureAccountsLoaded, ensureTradesLoaded } from "./appDataCache"
import { scheduleDeferredWork } from "./scheduleDeferredWork"
import { ensureTradingAccountsSettingsLoaded } from "./tradingAccountsSettingsCache"
import { ensureNotificationPreferencesLoaded } from "./notificationPreferencesCache"
import { ensureOwnAchievementsLoaded } from "./userAchievementsCache"

let warmedUserId: string | null = null
let prefetchGeneration = 0

/** Prefetch core caches after auth — recent trades window + accounts only.
 * Full trade history is loaded on-demand by dashboard/journal/etc.
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
  scheduleDeferredWork(() => {
    if (generation !== prefetchGeneration || warmedUserId !== id) return
    void (async () => {
      await Promise.all([
        ensureTradesLoaded(supabase, id).catch(() => []),
        ensureAccountsLoaded(supabase, id).catch(() => []),
      ])

      scheduleDeferredWork(() => {
        if (generation !== prefetchGeneration || warmedUserId !== id) return
        void Promise.all([
          ensureTradingAccountsSettingsLoaded(supabase, id).catch(() => []),
          ensureNotificationPreferencesLoaded(supabase, id).catch(() => null),
          ensureOwnAchievementsLoaded(supabase, id).catch(() => []),
        ])
      })
    })()
  }, 1000)
}

export function resetDataPrefetchSession() {
  prefetchGeneration += 1
  warmedUserId = null
}
