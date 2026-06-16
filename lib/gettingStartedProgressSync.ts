/** Fired when checklist-related user actions may have completed a task. */
export const GETTING_STARTED_SIGNALS_REFRESH_EVENT =
  "tradetraxs:getting-started-signals-refresh"

export type GettingStartedRefreshDetail = {
  /** True when a user action (trade save, follow, etc.) triggered the refresh. */
  fromUserAction?: boolean
}

export function dispatchGettingStartedSignalsRefresh(
  detail?: GettingStartedRefreshDetail
) {
  if (typeof window === "undefined") return
  window.dispatchEvent(
    new CustomEvent(GETTING_STARTED_SIGNALS_REFRESH_EVENT, { detail })
  )
}

/** Alias for call sites after a checklist-eligible action succeeds. */
export function notifyGettingStartedChecklistMaybeCompleted() {
  dispatchGettingStartedSignalsRefresh({ fromUserAction: true })
}

export function subscribeGettingStartedSignalsRefresh(
  listener: (detail?: GettingStartedRefreshDetail) => void
): () => void {
  if (typeof window === "undefined") return () => {}
  const handler = (event: Event) => {
    const custom = event as CustomEvent<GettingStartedRefreshDetail | undefined>
    listener(custom.detail)
  }
  window.addEventListener(GETTING_STARTED_SIGNALS_REFRESH_EVENT, handler)
  return () =>
    window.removeEventListener(GETTING_STARTED_SIGNALS_REFRESH_EVENT, handler)
}
