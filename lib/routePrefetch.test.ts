import { describe, it, beforeEach } from "node:test"
import type { AppRouterInstance } from "next/dist/shared/lib/app-router-context.shared-runtime"
import { APP_PREFETCH_CRITICAL_ROUTES, APP_PREFETCH_SECONDARY_ROUTES, prefetchCriticalAppRoutes, prefetchSecondaryAppRoutes, prefetchRouteOnIntent, resetRoutePrefetchSession, } from "./routePrefetch.ts"
import assert from "node:assert/strict"

function createPrefetchRouter(calls: string[]): AppRouterInstance {
  const router = {
    prefetch(href: string) {
      calls.push(href)
    },
  } satisfies Pick<AppRouterInstance, "prefetch">
  return router as AppRouterInstance
}

describe("routePrefetch (Phase B1)", () => {
  beforeEach(() => {
    resetRoutePrefetchSession()
  })

  it("secondary routes exclude community, explore, messages, profile", () => {
    const secondary: string[] = [...APP_PREFETCH_SECONDARY_ROUTES]
    assert.deepEqual(secondary, ["/trades", "/feed"])
    assert.ok(!secondary.includes("/community"))
    assert.ok(!secondary.includes("/explore"))
    assert.ok(!secondary.includes("/messages"))
  })

  it("critical routes include dashboard only", () => {
    assert.deepEqual([...APP_PREFETCH_CRITICAL_ROUTES], ["/dashboard"])
  })

  it("dedupes manual prefetch per href", () => {
    const calls: string[] = []
    const router = createPrefetchRouter(calls)
    prefetchCriticalAppRoutes(router, "/login")
    prefetchCriticalAppRoutes(router, "/login")
    prefetchRouteOnIntent(router, "/dashboard", "/login")
    assert.equal(calls.filter((h) => h === "/dashboard").length, 1)
  })

  it("skips prefetch for current route", () => {
    const calls: string[] = []
    const router = createPrefetchRouter(calls)
    prefetchCriticalAppRoutes(router, "/dashboard")
    assert.equal(calls.length, 0)
  })

  it("secondary prefetches trades and feed once when on dashboard", () => {
    const calls: string[] = []
    const router = createPrefetchRouter(calls)
    prefetchSecondaryAppRoutes(router, "/dashboard")
    prefetchSecondaryAppRoutes(router, "/dashboard")
    assert.deepEqual(calls, ["/trades", "/feed"])
  })
})
export {}
