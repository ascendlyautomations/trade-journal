"use client"

import { useEffect } from "react"
import { usePathname } from "next/navigation"
import {
  lockPageScroll,
  resetPageScrollLock,
  unlockPageScroll,
} from "@/lib/pageScrollLock"

/** Panel never exceeds the viewport (centered modals). */
export const MODAL_PANEL_MAX_HEIGHT_CLASS =
  "max-h-[min(90dvh,calc(100dvh-2rem))]"

/** Panel below the fixed navbar (`h-16`). */
export const MODAL_PANEL_MAX_HEIGHT_BELOW_NAV_CLASS =
  "max-h-[min(90dvh,calc(100dvh-4rem-2rem))]"

/**
 * Solid modal panel fill — page content must not show through the dialog.
 * Backdrop dimming stays on the overlay, separate from this surface.
 */
export const MODAL_PANEL_SURFACE_CLASS =
  "bg-[#0f172a]/95 backdrop-blur-xl"

export const MODAL_PANEL_SHELL_CLASS =
  `flex flex-col overflow-hidden rounded-xl border border-white/10 ${MODAL_PANEL_SURFACE_CLASS} text-gray-100 shadow-xl`

export const MODAL_BODY_SCROLL_CLASS =
  "min-h-0 flex-1 overflow-y-auto overscroll-contain"

export const MODAL_HEADER_CLASS = "shrink-0 border-b border-white/10"

export const MODAL_FOOTER_CLASS =
  `shrink-0 border-t border-white/10 ${MODAL_PANEL_SURFACE_CLASS}`

export { lockPageScroll, resetPageScrollLock, unlockPageScroll }

/** Prevent the page behind an open modal from scrolling (reference-counted). */
export function useModalScrollLock(open: boolean) {
  useEffect(() => {
    if (!open) return
    lockPageScroll()
    return () => {
      unlockPageScroll()
    }
  }, [open])
}

/** Resets scroll lock when the route changes so stale locks never persist. */
export function ScrollLockRouteReset() {
  const pathname = usePathname()

  useEffect(() => {
    resetPageScrollLock()
  }, [pathname])

  return null
}
