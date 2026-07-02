"use client"

import { useEffect } from "react"
import { enableDemoMode } from "@/lib/demo/demoMode"

/** Ensures demo fixtures are active for any /demo/* route (Phase 2 pages). */
export default function DemoRouteActivator() {
  useEffect(() => {
    enableDemoMode()
  }, [])
  return null
}
