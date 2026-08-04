"use client"

import type { ReactNode } from "react"
import { usePlatformPresentation } from "./usePlatformPresentation"

type PlatformCreateFlowProps = {
  /** Existing create / compose entry UI — unchanged on both platforms today. */
  children?: ReactNode
}

/**
 * Create-flow presentation adapter (compose, quick trade, post, etc.).
 */
export default function PlatformCreateFlow({ children }: PlatformCreateFlowProps) {
  const { isNativeIos } = usePlatformPresentation()
  if (isNativeIos) {
    return <>{children ?? null}</>
  }
  return <>{children ?? null}</>
}
