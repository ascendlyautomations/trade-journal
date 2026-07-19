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

if (window.location.pathname === "/") {
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
  window.setTimeout(startOnInteraction, 10_000)
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
