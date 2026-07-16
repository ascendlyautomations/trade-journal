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
  `flex flex-col overflow-hidden rounded-xl border border-white/15 ${MODAL_PANEL_SURFACE_CLASS} text-gray-100 shadow-xl`

export const MODAL_BODY_SCROLL_CLASS =
  "min-h-0 flex-1 overflow-y-auto overscroll-contain"

export const MODAL_HEADER_CLASS = "shrink-0 border-b border-white/10"

export const MODAL_FOOTER_CLASS =
  `shrink-0 border-t border-white/10 ${MODAL_PANEL_SURFACE_CLASS}`

/**
 * Modal stacking (lowest → highest among common overlays):
 * - DetailModalShell root: 9000
 * - ImageLightbox: 10001
 * - Modal / ScrollableModalShell / stacked DetailModalShell: 10050
 * - CommunitySharePreviewModal (preview over Quick/Add Trade): 10055
 * - FeedbackModal / ReelViewer: 10060
 * - Dropdown menus / CustomSelect portals: 10070 (DropdownMenu + ACCOUNT_DROPDOWN_PORTAL_MENU_CLASS)
 */
export const DETAIL_MODAL_Z_INDEX_CLASS = "z-[9000]"

/** Child DetailModalShell above another detail overlay (e.g. clip over trade). */
export const DETAIL_MODAL_STACKED_Z_INDEX_CLASS = "z-[10050]"

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

type EscapeLayer = {
  id: number
  onClose: () => void
}

let escapeLayerId = 0
const escapeLayers: EscapeLayer[] = []

/**
 * Escape closes only the topmost registered modal layer so stacked
 * DetailModalShells unwind one at a time.
 */
export function useStackedModalEscape(active: boolean, onClose: () => void) {
  useEffect(() => {
    if (!active) return

    const id = ++escapeLayerId
    const layer: EscapeLayer = { id, onClose }
    escapeLayers.push(layer)

    function onKey(e: KeyboardEvent) {
      if (e.key !== "Escape") return
      const top = escapeLayers[escapeLayers.length - 1]
      if (!top || top.id !== id) return
      e.preventDefault()
      e.stopPropagation()
      onClose()
    }

    window.addEventListener("keydown", onKey)
    return () => {
      window.removeEventListener("keydown", onKey)
      const idx = escapeLayers.findIndex((entry) => entry.id === id)
      if (idx >= 0) escapeLayers.splice(idx, 1)
    }
  }, [active, onClose])
}

/** Resets scroll lock when the route changes so stale locks never persist. */
export function ScrollLockRouteReset() {
  const pathname = usePathname()

  useEffect(() => {
    resetPageScrollLock()
  }, [pathname])

  return null
}
