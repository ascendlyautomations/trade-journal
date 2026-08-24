import type { GettingStartedChecklistSignals } from "./gettingStartedChecklistSignals.types.ts"

/**
 * Per-user session cache of the last *resolved* getting-started checklist
 * signals. Survives full page reloads within the tab, so returning users
 * restore their real completion state instantly instead of falling back to
 * the "nothing completed" defaults while the deferred signals fetch runs.
 */
const SIGNALS_CACHE_KEY_BASE = "tradetraxs_getting_started_signals_v1"

function storageKey(userId: string): string {
  return `${SIGNALS_CACHE_KEY_BASE}:${userId}`
}

export function readCachedGettingStartedSignals(
  userId: string
): GettingStartedChecklistSignals | null {
  if (typeof window === "undefined") return null
  try {
    const raw = window.sessionStorage.getItem(storageKey(userId))
    if (!raw) return null
    const parsed = JSON.parse(raw) as
      | Partial<GettingStartedChecklistSignals>
      | null
    if (!parsed || typeof parsed !== "object") return null
    return {
      onboardingCompleted: parsed.onboardingCompleted === true,
      hasSeenGettingStartedIntro: parsed.hasSeenGettingStartedIntro === true,
      hasSeenOnboardingCompletePopup:
        parsed.hasSeenOnboardingCompletePopup === true,
      tradeCount:
        typeof parsed.tradeCount === "number" && parsed.tradeCount >= 0
          ? parsed.tradeCount
          : 0,
      profilePostCount:
        typeof parsed.profilePostCount === "number" &&
        parsed.profilePostCount >= 0
          ? parsed.profilePostCount
          : 0,
      followCount:
        typeof parsed.followCount === "number" && parsed.followCount >= 0
          ? parsed.followCount
          : 0,
      hasEverJoinedOtherRoom: parsed.hasEverJoinedOtherRoom === true,
      hasPublicTrade: parsed.hasPublicTrade === true,
      firstPrivateTradeId:
        typeof parsed.firstPrivateTradeId === "string"
          ? parsed.firstPrivateTradeId
          : null,
    }
  } catch {
    return null
  }
}

export function writeCachedGettingStartedSignals(
  userId: string,
  signals: GettingStartedChecklistSignals
) {
  if (typeof window === "undefined") return
  try {
    window.sessionStorage.setItem(storageKey(userId), JSON.stringify(signals))
  } catch {
    /* ignore quota / private mode */
  }
}

/** Sign-out / account switch: drop every user's cached signals. */
export function clearAllCachedGettingStartedSignals() {
  if (typeof window === "undefined") return
  try {
    const stale: string[] = []
    for (let i = 0; i < window.sessionStorage.length; i += 1) {
      const key = window.sessionStorage.key(i)
      if (key && key.startsWith(`${SIGNALS_CACHE_KEY_BASE}:`)) {
        stale.push(key)
      }
    }
    for (const key of stale) {
      window.sessionStorage.removeItem(key)
    }
  } catch {
    /* ignore private mode */
  }
}
