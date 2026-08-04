"use client"

import type { ReactNode } from "react"
import { usePlatformPresentation } from "./usePlatformPresentation"

type PlatformPageHeaderProps = {
  /** Optional title for future native navigation bars. Unused while identical. */
  title?: string
  /** Existing page header markup — rendered as-is on both platforms today. */
  children?: ReactNode
}

/**
 * Page header presentation adapter.
 * Pass existing header UI as children; both platforms render it unchanged.
 */
export default function PlatformPageHeader({
  children,
}: PlatformPageHeaderProps) {
  const { isNativeIos } = usePlatformPresentation()
  if (isNativeIos) {
    return <>{children}</>
  }
  return <>{children}</>
}
