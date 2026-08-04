"use client"

import Link from "next/link"
import { TrendingUp } from "lucide-react"
import { NATIVE_IOS_PAGE_HEADER_ACTION_CLASS } from "@/app/components/platform/PlatformPageHeader"
import { hapticLight } from "@/lib/nativeHaptics"
import { usePlatformPresentation } from "./usePlatformPresentation"

/**
 * Native iOS Dashboard only — Trades shortcut in the page header.
 * Web returns null.
 */
export default function PlatformDashboardTradesButton() {
  const { isNativeIos } = usePlatformPresentation()
  if (!isNativeIos) return null

  return (
    <Link
      href="/trades"
      aria-label="Trades"
      title="Trades"
      className={NATIVE_IOS_PAGE_HEADER_ACTION_CLASS}
      onClick={() => hapticLight("trades")}
    >
      <TrendingUp className="h-[18px] w-[18px]" strokeWidth={2} aria-hidden />
    </Link>
  )
}
