import { getBaseSentryOptions } from "./lib/sentry"

let sentryPromise: Promise<typeof import("@sentry/nextjs")> | null = null

function loadSentry() {
  if (!sentryPromise) {
    sentryPromise = import("@sentry/nextjs").then((Sentry) => {
      Sentry.init({
        ...getBaseSentryOptions(),
      })
      return Sentry
    })
  }
  return sentryPromise
}

/** Native shell markers (cookie / UA) — do not import Capacitor. */
function isNativeShellClient(): boolean {
  try {
    if (/(?:^|;\s*)tt_native=1(?:;|$)/.test(document.cookie)) return true
  } catch {
    // ignore
  }
  try {
    return /TradeTraxsNative/i.test(navigator.userAgent)
  } catch {
    return false
  }
}

function deferSentryUntilIdle(delayMs: number) {
  const startOnInteraction = () => {
    void loadSentry()
  }
  const captureEarlyError = (event: ErrorEvent) => {
    void loadSentry().then((Sentry) => {
      Sentry.captureException(event.error ?? new Error(event.message))
    })
  }
  const captureEarlyRejection = (event: PromiseRejectionEvent) => {
    void loadSentry().then((Sentry) => {
      Sentry.captureException(event.reason)
    })
  }
  window.addEventListener("pointerdown", startOnInteraction, { once: true })
  window.addEventListener("keydown", startOnInteraction, { once: true })
  window.addEventListener("error", captureEarlyError, { once: true })
  window.addEventListener("unhandledrejection", captureEarlyRejection, {
    once: true,
  })
  window.setTimeout(startOnInteraction, delayMs)
}

// Marketing homepage + native Capacitor shell: don't compete with first paint.
// Web non-homepage behavior is unchanged (immediate init).
if (window.location.pathname === "/") {
  deferSentryUntilIdle(10_000)
} else if (isNativeShellClient()) {
  deferSentryUntilIdle(8_000)
} else {
  void loadSentry()
}

export function onRouterTransitionStart(
  href: string,
  navigationType: string
) {
  void loadSentry().then((Sentry) => {
    Sentry.captureRouterTransitionStart(href, navigationType)
  })
}
