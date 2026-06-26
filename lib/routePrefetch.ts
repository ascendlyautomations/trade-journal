import type { AppRouterInstance } from "next/dist/shared/lib/app-router-context.shared-runtime"

/** Core authenticated routes — prefetch for near-instant navigation. */
export const APP_PREFETCH_ROUTES = [
  "/dashboard",
  "/trades",
  "/feed",
  "/messages",
  "/notifications",
  "/explore",
  "/settings",
  "/calendar",
] as const

let prefetchedForSession = false

export function prefetchAppRoutes(router: AppRouterInstance) {
  if (prefetchedForSession) return
  prefetchedForSession = true
  for (const href of APP_PREFETCH_ROUTES) {
    try {
      router.prefetch(href)
    } catch {
      // ignore prefetch failures (offline, etc.)
    }
  }
}

export function resetRoutePrefetchSession() {
  prefetchedForSession = false
}
