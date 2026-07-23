"use client"

import { useEffect, useState } from "react"
import { isNativeIos } from "@/lib/nativePlatform"

/** Client-only gate — false during SSR/hydration, then true on Capacitor iOS. */
export function useIsNativeIos(): boolean {
  const [enabled, setEnabled] = useState(false)
  useEffect(() => {
    setEnabled(isNativeIos())
  }, [])
  return enabled
}
