"use client"

import type { ReactNode } from "react"
import { usePlatformPresentation } from "./usePlatformPresentation"

type PlatformSettingsEntryProps = {
  /** Existing settings entry UI — unchanged on both platforms today. */
  children?: ReactNode
}

/**
 * Settings entry presentation adapter.
 */
export default function PlatformSettingsEntry({
  children,
}: PlatformSettingsEntryProps) {
  const { isNativeIos } = usePlatformPresentation()
  if (isNativeIos) {
    return <>{children ?? null}</>
  }
  return <>{children ?? null}</>
}
