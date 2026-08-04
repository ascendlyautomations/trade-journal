"use client"

import { useIsNativeIos } from "@/lib/useIsNativeIos"

/**
 * Presentation-only platform gate.
 * Reuses existing native detection — do not invent a second system.
 */
export function usePlatformPresentation(): {
  /** Capacitor iOS shell (false on web / SSR / first paint). */
  isNativeIos: boolean
  /** Responsive website (mobile or desktop). */
  isWeb: boolean
} {
  const isNativeIos = useIsNativeIos()
  return { isNativeIos, isWeb: !isNativeIos }
}
