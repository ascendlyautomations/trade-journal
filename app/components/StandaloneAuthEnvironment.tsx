"use client"

import { useEffect, type ReactNode } from "react"
import { syncDemoBannerLayout } from "@/lib/demo/demoLayout"

/** Ensures standalone auth screens never reserve demo-banner / navbar layout offsets. */
export default function StandaloneAuthEnvironment({
  children,
}: {
  children: ReactNode
}) {
  useEffect(() => {
    syncDemoBannerLayout(false)
  }, [])

  return <>{children}</>
}
