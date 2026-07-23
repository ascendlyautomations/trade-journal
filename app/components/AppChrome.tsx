"use client"

import dynamic from "next/dynamic"
import { usePathname, useSelectedLayoutSegments } from "next/navigation"
import type { ReactNode } from "react"
import { shouldMountGlobalAppNavbar } from "@/lib/layoutChrome"
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
 * Capacitor iOS also mounts a persistent bottom tab bar (web unchanged).
 */
export default function AppChrome({ children }: { children: ReactNode }) {
  const pathname = usePathname()
  const segments = useSelectedLayoutSegments()
  const showAppNavbar = shouldMountGlobalAppNavbar(pathname, segments)
  const nativeIos = useIsNativeIos()

  if (!showAppNavbar) {
    return <div className="flex w-full flex-col">{children}</div>
  }

  return (
    <>
      <Navbar />
      <div
        className={`flex w-full flex-col pt-[var(--app-header-offset)]${
          nativeIos
            ? " pb-[calc(var(--app-tab-bar-height)+var(--safe-area-bottom))]"
            : ""
        }`}
      >
        {children}
      </div>
      {nativeIos ? <NativeIosBottomNav /> : null}
    </>
  )
}
