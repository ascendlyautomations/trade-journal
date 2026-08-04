"use client"

import type { ReactNode } from "react"
import { usePlatformPresentation } from "./usePlatformPresentation"

type PlatformNotificationsProps = {
  /** Existing notifications UI — rendered as-is on both platforms today. */
  children?: ReactNode
}

/**
 * Notifications presentation adapter.
 * Today notifications live in Navbar; wrap extracted UI here when diverging.
 */
export default function PlatformNotifications({
  children,
}: PlatformNotificationsProps) {
  const { isNativeIos } = usePlatformPresentation()
  if (isNativeIos) {
    return <>{children ?? null}</>
  }
  return <>{children ?? null}</>
}
