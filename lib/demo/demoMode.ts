export const DEMO_MODE_STORAGE_KEY = "tradetraxs_demo_mode"
export const DEMO_MODE_CHANGE_EVENT = "tradetraxs-demo-mode"

export function isDemoModeActive(): boolean {
  if (typeof window === "undefined") return false
  return sessionStorage.getItem(DEMO_MODE_STORAGE_KEY) === "1"
}

/** Preview/Demo UI (e.g. "Return to App") — session flag only, never pathname-based. */
export function isPreviewExperienceActive(): boolean {
  return isDemoModeActive()
}

export function enableDemoMode(): void {
  if (typeof window === "undefined") return
  sessionStorage.setItem(DEMO_MODE_STORAGE_KEY, "1")
  window.dispatchEvent(new Event(DEMO_MODE_CHANGE_EVENT))
}

export function disableDemoMode(): void {
  if (typeof window === "undefined") return
  sessionStorage.removeItem(DEMO_MODE_STORAGE_KEY)
  window.dispatchEvent(new Event(DEMO_MODE_CHANGE_EVENT))
}

/** Fully leave demo — clears the session flag and notifies all demo listeners. */
export function exitDemoMode(): void {
  if (typeof window === "undefined") return
  if (!isDemoModeActive()) return
  disableDemoMode()
}

export function subscribeDemoModeChanges(listener: () => void): () => void {
  if (typeof window === "undefined") return () => {}
  window.addEventListener(DEMO_MODE_CHANGE_EVENT, listener)
  return () => window.removeEventListener(DEMO_MODE_CHANGE_EVENT, listener)
}
