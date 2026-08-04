"use client"

import type { ReactNode } from "react"
import NativeIosCalendarHeader, {
  type NativeIosCalendarHeaderProps,
} from "./native/NativeIosCalendarHeader"
import { usePlatformPresentation } from "./usePlatformPresentation"

export type PlatformCalendarHeaderProps = NativeIosCalendarHeaderProps

/**
 * Calendar page chrome adapter.
 * Native iOS: compact sticky filter header. Web: null (page filters unchanged).
 */
export default function PlatformCalendarHeader(
  props: PlatformCalendarHeaderProps
) {
  const { isNativeIos } = usePlatformPresentation()
  if (!isNativeIos) return null
  return <NativeIosCalendarHeader {...props} />
}

/**
 * In-flow Calendar account/mode filters for web (desktop + mobile Safari).
 * Hidden on native iOS where the same controls live in PlatformCalendarHeader.
 */
export function PlatformCalendarFilters({
  children,
}: {
  children: ReactNode
}) {
  const { isNativeIos } = usePlatformPresentation()
  if (isNativeIos) return null
  return <>{children}</>
}
