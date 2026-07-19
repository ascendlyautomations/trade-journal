/**
 * Central session-scoped user data cache lifecycle.
 * Valid until sign-out, explicit invalidation, or profile/subscription/settings change.
 */

import {
  clearUserBootstrapProfile,
  clearAllUserBootstrapProfiles,
} from "./userBootstrapCache"
import { clearAllNotificationPreferencesCaches } from "./notificationPreferencesCache"
import {
  clearSettingsProfileCache,
  clearAllSettingsProfileCaches,
} from "./settingsProfileCache"
import { clearAllTradingAccountsSettingsCaches } from "./tradingAccountsSettingsCache"
import { clearAllUserAchievementsCaches } from "./userAchievementsCache"
import { clearAllUserStreaksCaches } from "./userStreaksCache"
import { clearAllCachedGettingStartedSignals } from "./gettingStartedSignalsCache"

/** Clear every session-scoped user cache (sign-out / account switch). */
export function clearAllSessionUserDataCaches() {
  clearAllUserBootstrapProfiles()
  clearAllSettingsProfileCaches()
  clearAllNotificationPreferencesCaches()
  clearAllTradingAccountsSettingsCaches()
  clearAllUserAchievementsCaches()
  clearAllUserStreaksCaches()
  clearAllCachedGettingStartedSignals()
}

/** Profile or subscription fields changed — drop extended profile + bootstrap slices. */
export function invalidateSessionProfileCaches(userId: string) {
  const key = userId.trim()
  if (!key) return
  clearSettingsProfileCache(key)
  clearUserBootstrapProfile(key)
}

/** Settings form saved — extended profile row was already written; achievements unchanged. */
export function invalidateSessionSettingsCaches(userId: string) {
  invalidateSessionProfileCaches(userId)
}
