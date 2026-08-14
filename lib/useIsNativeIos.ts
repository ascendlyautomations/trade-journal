"use client"

import { useEffect, useState } from "react"
import { isNativeIos } from "@/lib/nativePlatform"

/** Client-only gate — false during SSR/hydration, then true on native iOS shell markers. */
export function useIsNativeIos(): boolean {
  const [enabled, setEnabled] = useState(false)
  useEffect(() => {
    setEnabled(isNativeIos())
  }, [])
  return enabled
}
