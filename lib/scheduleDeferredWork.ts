/** Run work after first paint — avoids competing with login → dashboard critical path. */
export function scheduleDeferredWork(work: () => void, timeoutMs = 1500): void {
  if (typeof window === "undefined") {
    work()
    return
  }
  if (typeof requestIdleCallback === "function") {
    requestIdleCallback(
      () => {
        work()
      },
      { timeout: timeoutMs }
    )
    return
  }
  setTimeout(work, 50)
}
