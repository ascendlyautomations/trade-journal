"use client"

import type { ReactNode } from "react"
import { useIsNativeIos } from "@/lib/useIsNativeIos"

/** Phone-web only. Hidden at 768px+ and omitted in Capacitor native. */
export function MobileWebViewport({ children }: { children: ReactNode }) {
  const isNativeIos = useIsNativeIos()
  if (isNativeIos) return null
  return <div className="md:hidden">{children}</div>
}

/** Existing desktop/tablet (and Capacitor) presentation. Hidden below 768px on web. */
export function DesktopWebViewport({ children }: { children: ReactNode }) {
  const isNativeIos = useIsNativeIos()
  if (isNativeIos) return <>{children}</>
  return <div className="hidden md:block">{children}</div>
}
