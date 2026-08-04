"use client"

import type { ReactNode } from "react"
import PlatformBottomNavigation from "../PlatformBottomNavigation"

/**
 * Native iOS chrome layout — identical to the previous AppChrome native branch.
 * Scrollport + tab bar geometry unchanged.
 */
export default function NativeIosAppChrome({
  children,
}: {
  children: ReactNode
}) {
  return (
    <>
      {/*
        Content ends exactly at --app-tab-bar-offset (49px item row +
        env(safe-area-inset-bottom)). That matches .tt-ios-tab-bar total
        height — one bar, no body-colored gap above it.
      */}
      {/*
        Full-bleed scroll under the fixed top navbar so auto-hide can reveal
        content via translateY only (no padding/layout changes while scrolling).
        Static pt matches --app-header-offset; bottom inset clears the tab bar.
      */}
      <div
        data-tt-app-scroll
        className="fixed inset-x-0 top-0 bottom-[var(--app-tab-bar-offset)] flex w-full flex-col overflow-x-hidden overflow-y-auto overscroll-y-contain bg-[var(--tt-surface)]"
      >
        <div className="flex min-h-full w-full flex-col pt-[var(--app-header-offset)]">
          {children}
        </div>
      </div>
      <PlatformBottomNavigation />
    </>
  )
}
