import type { SupabaseClient } from "@supabase/supabase-js"
import { isDemoUserId } from "./demo/constants"
import { seedDemoCaches } from "./demo/demoUser"
import { ensureAccountsLoaded, ensureTradesLoaded } from "./appDataCache"
import { fetchSettingsProfileRow } from "./settingsProfileSync"
import { scheduleDeferredWork } from "./scheduleDeferredWork"
import { ensureTradingAccountsSettingsLoaded } from "./tradingAccountsSettingsCache"
import { ensureNotificationPreferencesLoaded } from "./notificationPreferencesCache"
import { ensureOwnAchievementsLoaded } from "./userAchievementsCache"

let warmedUserId: string | null = null

/** Prefetch core caches after auth — speeds first navigation to dashboard, trades, and settings. */
export function warmAppDataCaches(
  supabase: SupabaseClient,
  userId: string
) {
  const id = userId.trim()
  if (!id || warmedUserId === id) return
  warmedUserId = id
  if (isDemoUserId(id)) {
    seedDemoCaches()
    return
  }
  void Promise.all([
    ensureTradesLoaded(supabase, id),
    ensureAccountsLoaded(supabase, id),
    fetchSettingsProfileRow(supabase, id).catch(() => null),
  ])
  scheduleDeferredWork(() => {
    void Promise.all([
      ensureTradingAccountsSettingsLoaded(supabase, id).catch(() => []),
      ensureNotificationPreferencesLoaded(supabase, id).catch(() => null),
      ensureOwnAchievementsLoaded(supabase, id).catch(() => []),
    ])
  })
}

export function resetDataPrefetchSession() {
  warmedUserId = null
}
