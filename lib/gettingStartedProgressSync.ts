/** Fired when checklist-related user actions may have completed a task. */
export const GETTING_STARTED_SIGNALS_REFRESH_EVENT =
  "tradetraxs:getting-started-signals-refresh"

export function dispatchGettingStartedSignalsRefresh() {
  if (typeof window === "undefined") return
  window.dispatchEvent(new CustomEvent(GETTING_STARTED_SIGNALS_REFRESH_EVENT))
}

/** Alias for call sites after a checklist-eligible action succeeds. */
export function notifyGettingStartedChecklistMaybeCompleted() {
  dispatchGettingStartedSignalsRefresh()
}

export function subscribeGettingStartedSignalsRefresh(
  listener: () => void
): () => void {
  if (typeof window === "undefined") return () => {}
  window.addEventListener(GETTING_STARTED_SIGNALS_REFRESH_EVENT, listener)
  return () =>
    window.removeEventListener(GETTING_STARTED_SIGNALS_REFRESH_EVENT, listener)
}
