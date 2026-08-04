"use client"

import type { ReactNode } from "react"
import { usePlatformPresentation } from "./usePlatformPresentation"

type PlatformSearchProps = {
  /** Existing search UI — rendered as-is on both platforms today. */
  children?: ReactNode
}

/**
 * Search presentation adapter.
 * Wire existing search chrome as children; diverge native later without page changes.
 */
export default function PlatformSearch({ children }: PlatformSearchProps) {
  const { isNativeIos } = usePlatformPresentation()
  if (isNativeIos) {
    return <>{children ?? null}</>
  }
  return <>{children ?? null}</>
}
