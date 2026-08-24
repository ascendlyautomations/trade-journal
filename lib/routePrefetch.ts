import type { AppRouterInstance } from "next/dist/shared/lib/app-router-context.shared-runtime"

/** Immediately after login — dashboard only (when not already there). */
export const APP_PREFETCH_CRITICAL_ROUTES = ["/dashboard"] as const

/**
 * After dashboard is interactive — next most likely tabs only.
 * Excludes community/explore/messages/profile (intent-hover or click).
 */
export const APP_PREFETCH_SECONDARY_ROUTES = ["/trades", "/feed"] as const

const prefetchedHrefs = new Set<string>()
let criticalPrefetchDone = false
let secondaryPrefetchDone = false
let prefetchGeneration = 0

function normalizeHref(href: string): string | null {
  const trimmed = href.trim()
  if (!trimmed || !trimmed.startsWith("/")) return null
  return trimmed.split("?")[0] ?? trimmed
}

function isCurrentOrChildRoute(href: string, currentPathname?: string): boolean {
  if (!currentPathname) return false
  const current = normalizeHref(currentPathname)
  if (!current) return false
  return current === href || current.startsWith(`${href}/`)
}

function prefetchRoute(
  router: AppRouterInstance,
  href: string,
  currentPathname?: string
) {
  const normalized = normalizeHref(href)
  if (!normalized || prefetchedHrefs.has(normalized)) return
  if (isCurrentOrChildRoute(normalized, currentPathname)) return
  prefetchedHrefs.add(normalized)
  try {
    router.prefetch(normalized)
  } catch {
    // offline / unsupported — non-fatal
  }
}

/** Prefetch dashboard once auth is ready (skips when already on dashboard). */
export function prefetchCriticalAppRoutes(
  router: AppRouterInstance,
  currentPathname?: string
) {
  if (criticalPrefetchDone) return
  criticalPrefetchDone = true
  for (const href of APP_PREFETCH_CRITICAL_ROUTES) {
    prefetchRoute(router, href, currentPathname)
  }
}

/** Prefetch high-traffic routes once dashboard is interactive (deduped, no profile). */
export function prefetchSecondaryAppRoutes(
  router: AppRouterInstance,
  currentPathname?: string
) {
  if (secondaryPrefetchDone) return
  secondaryPrefetchDone = true
  for (const href of APP_PREFETCH_SECONDARY_ROUTES) {
    prefetchRoute(router, href, currentPathname)
  }
}

/** Intent-based prefetch (hover / focus / tap) — deduped per session. */
export function prefetchRouteOnIntent(
  router: AppRouterInstance,
  href: string,
  currentPathname?: string
) {
  prefetchRoute(router, href, currentPathname)
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
