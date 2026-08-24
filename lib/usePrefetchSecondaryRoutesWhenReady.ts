"use client"

import { useEffect } from "react"
import { usePathname, useRouter } from "next/navigation"
import { prefetchSecondaryAppRoutes } from "@/lib/routePrefetch"
import { scheduleDeferredWork } from "@/lib/scheduleDeferredWork"

/** Prefetch trades + feed after dashboard is interactive (not profile/community/explore). */
export function usePrefetchSecondaryRoutesWhenReady(ready: boolean) {
  const router = useRouter()
  const pathname = usePathname() ?? "/"

  useEffect(() => {
    if (!ready) return
    scheduleDeferredWork(() => {
      prefetchSecondaryAppRoutes(router, pathname)
    }, 2500)
  }, [ready, pathname, router])
}
