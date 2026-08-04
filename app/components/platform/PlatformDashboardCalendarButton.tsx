"use client"

import Link from "next/link"
import { Calendar } from "lucide-react"
import { NATIVE_IOS_PAGE_HEADER_ACTION_CLASS } from "@/app/components/platform/PlatformPageHeader"
import { hapticLight } from "@/lib/nativeHaptics"
import { usePlatformPresentation } from "./usePlatformPresentation"

/**
 * Native iOS Dashboard only — calendar icon in the page header.
 * Web returns null (mobile + desktop filter bar unchanged).
 */
export default function PlatformDashboardCalendarButton() {
  const { isNativeIos } = usePlatformPresentation()
  if (!isNativeIos) return null

  return (
    <Link
      href="/calendar"
      aria-label="Calendar"
      className={NATIVE_IOS_PAGE_HEADER_ACTION_CLASS}
      onClick={() => hapticLight("calendar")}
    >
      <Calendar className="h-[18px] w-[18px]" strokeWidth={2} aria-hidden />
    </Link>
  )
}
