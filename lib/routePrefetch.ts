import type { AppRouterInstance } from "next/dist/shared/lib/app-router-context.shared-runtime"

/** Immediately after login — dashboard only. */
export const APP_PREFETCH_CRITICAL_ROUTES = ["/dashboard"] as const

/** After dashboard is interactive — highest-probability destinations. */
export const APP_PREFETCH_SECONDARY_ROUTES = [
  "/trades",
  "/feed",
  "/messages",
  "/community",
  "/explore",
] as const

const prefetchedHrefs = new Set<string>()
let criticalPrefetchDone = false
let secondaryPrefetchDone = false
let prefetchGeneration = 0

function normalizeHref(href: string): string | null {
  const trimmed = href.trim()
  if (!trimmed || !trimmed.startsWith("/")) return null
  return trimmed
}

function prefetchRoute(router: AppRouterInstance, href: string) {
  const normalized = normalizeHref(href)
  if (!normalized || prefetchedHrefs.has(normalized)) return
  prefetchedHrefs.add(normalized)
  try {
    router.prefetch(normalized)
  } catch {
    // offline / unsupported — non-fatal
  }
}

/** Prefetch dashboard as soon as auth is ready (login critical path). */
export function prefetchCriticalAppRoutes(router: AppRouterInstance) {
  if (criticalPrefetchDone) return
  criticalPrefetchDone = true
  for (const href of APP_PREFETCH_CRITICAL_ROUTES) {
    prefetchRoute(router, href)
  }
}

/** Prefetch high-traffic routes once dashboard is fully interactive. */
export function prefetchSecondaryAppRoutes(
  router: AppRouterInstance,
  profileHref?: string | null
) {
  if (secondaryPrefetchDone) return
  secondaryPrefetchDone = true
  const routes = [
    ...APP_PREFETCH_SECONDARY_ROUTES,
    ...(profileHref ? [profileHref] : []),
  ]
  if (typeof window === "undefined") {
    for (const href of routes) prefetchRoute(router, href)
    return
  }
  const generation = prefetchGeneration
  routes.forEach((href, index) => {
    window.setTimeout(() => {
      if (generation === prefetchGeneration) prefetchRoute(router, href)
    }, index * 250)
  })
}

/** Intent-based prefetch (hover / focus / tap) — deduped per session. */
export function prefetchRouteOnIntent(
  router: AppRouterInstance,
  href: string
) {
  prefetchRoute(router, href)
}

export function resetRoutePrefetchSession() {
  prefetchGeneration += 1
  criticalPrefetchDone = false
  secondaryPrefetchDone = false
  prefetchedHrefs.clear()
}

/** @deprecated Use prefetchCriticalAppRoutes + prefetchSecondaryAppRoutes */
export function prefetchAppRoutes(router: AppRouterInstance) {
  prefetchCriticalAppRoutes(router)
}
