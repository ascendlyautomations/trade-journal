"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { prefetchSecondaryAppRoutes } from "@/lib/routePrefetch"
import { scheduleDeferredWork } from "@/lib/scheduleDeferredWork"

/** Prefetch trades / feed / messages / profile after dashboard is interactive. */
export function usePrefetchSecondaryRoutesWhenReady(
  ready: boolean,
  profileHref: string | null | undefined
) {
  const router = useRouter()

  useEffect(() => {
    if (!ready) return
    scheduleDeferredWork(() => {
      prefetchSecondaryAppRoutes(router, profileHref)
    }, 2500)
  }, [ready, profileHref, router])
}
