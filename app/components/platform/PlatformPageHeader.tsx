"use client"

import type { ReactNode } from "react"
import { usePlatformPresentation } from "./usePlatformPresentation"
import NativeIosPageHeader, {
  type NativeIosPageHeaderProps,
} from "./native/NativeIosPageHeader"

export type PlatformPageHeaderProps = NativeIosPageHeaderProps & {
  /**
   * Web-only fallback. When provided on web, rendered as-is.
   * Native iOS always uses the standardized header chrome.
   */
  children?: ReactNode
}

/**
 * Standard page header adapter.
 * Native iOS: shared compact header. Web: existing children (or null).
 */
export default function PlatformPageHeader({
  children,
  title,
  leftContent,
  rightActions,
  sticky,
  className,
}: PlatformPageHeaderProps) {
  const { isNativeIos } = usePlatformPresentation()

  if (!isNativeIos) {
    return children != null ? <>{children}</> : null
  }

  return (
    <NativeIosPageHeader
      title={title}
      leftContent={leftContent}
      rightActions={rightActions}
      sticky={sticky}
      className={className}
    />
  )
}

export { NATIVE_IOS_PAGE_HEADER_ACTION_CLASS } from "./native/NativeIosPageHeader"
