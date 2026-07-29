"use client"

import dynamic from "next/dynamic"
import { usePathname, useSelectedLayoutSegments } from "next/navigation"
import type { ReactNode } from "react"
import { shouldMountGlobalAppNavbar } from "@/lib/layoutChrome"
import { isDmConversationPath } from "@/lib/messageRoutes"
import { useIsNativeIos } from "@/lib/useIsNativeIos"
import NativeIosBottomNav from "./NativeIosBottomNav"

/**
 * Navbar is a large client module (realtime, menus, demo, etc.). Load it only
 * when app chrome actually mounts so /login and other standalone routes never
 * pay for its parse cost. Padding uses --app-header-offset so content does not
 * shift when the chunk arrives.
 */
const Navbar = dynamic(() => import("./Navbar"), {
  ssr: false,
  loading: () => null,
})

/**
 * Root app chrome: mounts the portaled app Navbar only on routes that need it.
 * Auth/marketing/legal/demo/standalone flows never mount Navbar (no CSS hiding).
 * Capacitor iOS also mounts a persistent bottom tab bar (web unchanged),
 * except inside DM conversations (Instagram-style full-screen thread).
 */
export default function AppChrome({ children }: { children: ReactNode }) {
  const pathname = usePathname()
  const segments = useSelectedLayoutSegments()
  const showAppNavbar = shouldMountGlobalAppNavbar(pathname, segments)
  const nativeIos = useIsNativeIos()
  const nativeDmFullscreen = nativeIos && isDmConversationPath(pathname)

  if (!showAppNavbar) {
    return <div className="flex w-full flex-col">{children}</div>
  }

  if (nativeDmFullscreen) {
    return <div className="flex min-h-0 w-full flex-col">{children}</div>
  }

  if (nativeIos) {
    return (
      <>
        <Navbar />
        {/*
          Content ends exactly at --app-tab-bar-offset (49px item row +
          env(safe-area-inset-bottom)). That matches .tt-ios-tab-bar total
          height — one bar, no body-colored gap above it.
        */}
        <div className="fixed inset-x-0 top-[var(--app-header-offset)] bottom-[var(--app-tab-bar-offset)] flex w-full flex-col overflow-x-hidden overflow-y-auto overscroll-y-contain bg-[var(--tt-surface)]">
          <div className="flex min-h-full w-full flex-col">{children}</div>
        </div>
        <NativeIosBottomNav />
      </>
    )
  }

  return (
    <>
      <Navbar />
      <div className="flex w-full flex-col pt-[var(--app-header-offset)]">
        {children}
      </div>
    </>
  )
}
