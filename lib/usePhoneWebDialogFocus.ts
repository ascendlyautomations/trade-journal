"use client"

import { useEffect, type RefObject } from "react"
import {
  nextDialogFocusIndex,
  phoneWebDialogFocusables,
} from "./mobileWebA11y.ts"
import { isPhoneWebTouchTarget } from "./mobileWebTouch.ts"

/**
 * Keep Tab inside a phone-web dialog and return focus on close.
 * No-ops on native iOS and at ≥768px.
 */
export function usePhoneWebDialogFocus(
  open: boolean,
  containerRef: RefObject<HTMLElement | null>
) {
  useEffect(() => {
    if (!open || !isPhoneWebTouchTarget()) return
    const root = containerRef.current
    if (!root) return

    const previous =
      document.activeElement instanceof HTMLElement
        ? document.activeElement
        : null
    const initial = phoneWebDialogFocusables(root)
    initial[0]?.focus()

    function onKeyDown(event: KeyboardEvent) {
      if (event.key !== "Tab" || !root) return
      const items = phoneWebDialogFocusables(root)
      if (items.length === 0) return
      const active = document.activeElement
      const index = items.findIndex((item) => item === active)
      const next = nextDialogFocusIndex(
        index,
        items.length,
        event.shiftKey
      )
      event.preventDefault()
      items[next]?.focus()
    }

    root.addEventListener("keydown", onKeyDown)
    return () => {
      root.removeEventListener("keydown", onKeyDown)
      if (previous && document.contains(previous)) previous.focus()
    }
  }, [open, containerRef])
}
