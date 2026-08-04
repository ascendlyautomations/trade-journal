"use client"

import type { ReactNode } from "react"
import PlatformBottomNavigation from "../PlatformBottomNavigation"

/**
 * Native iOS chrome layout — scrollport + tab bar.
 * `safeAreaOnlyTopInset`: no website Navbar (Dashboard / Feed / Calendar /
 * Trades / Messages inbox / Add Trade) — pad with safe-area-top only.
 */
export default function NativeIosAppChrome({
  children,
  safeAreaOnlyTopInset = false,
}: {
  children: ReactNode
  safeAreaOnlyTopInset?: boolean
}) {
  return (
    <>
      {/*
        Content ends exactly at --app-tab-bar-offset (49px item row +
        env(safe-area-inset-bottom)). That matches .tt-ios-tab-bar total
        height — one bar, no body-colored gap above it.
      */}
      <div
        data-tt-app-scroll
        data-tt-native-no-web-navbar={safeAreaOnlyTopInset ? "1" : undefined}
        className="fixed inset-x-0 top-0 bottom-[var(--app-tab-bar-offset)] flex w-full flex-col overflow-x-hidden overflow-y-auto overscroll-y-contain bg-[var(--tt-surface)]"
      >
        <div
          className={
            safeAreaOnlyTopInset
              ? "flex min-h-full w-full flex-col pt-[var(--safe-area-top)]"
              : "flex min-h-full w-full flex-col pt-[var(--app-header-offset)]"
          }
        >
          {children}
        </div>
      </div>
      <PlatformBottomNavigation />
    </>
  )
}
