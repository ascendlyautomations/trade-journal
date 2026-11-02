"use client"

import { useEffect } from "react"
import { keyboardHeightFromViewport } from "@/lib/mobileWebKeyboard"
import { shouldDismissKeyboardOnTouchMove } from "@/lib/mobileWebTouch"
import { isNativeIos } from "@/lib/nativePlatform"

const FIELD_SELECTOR = "input, textarea, select, [contenteditable='true']"
const KEYBOARD_OPEN_CLASS = "tt-mobile-web-keyboard-open"

/**
 * Phone web: dragging the page dismisses the keyboard (SwiftUI scroll-dismiss).
 * A drag that starts on the field itself is left alone so caret movement still works.
 * Native iOS keeps its own keyboard inset. Desktop is unchanged.
 */
export default function MobileWebTouchRoot() {
  useEffect(() => {
    let startY = 0
    let startedOnField = false

    const phoneWeb = () => {
      if (isNativeIos()) return false
      return window.matchMedia("(max-width: 767px)").matches
    }

    const onStart = (event: TouchEvent) => {
      if (!phoneWeb()) return
      const touch = event.touches[0]
      if (!touch) return
      startY = touch.clientY
      const target = event.target
      startedOnField =
        target instanceof Element && Boolean(target.closest(FIELD_SELECTOR))
    }

    const onMove = (event: TouchEvent) => {
      if (!phoneWeb() || startedOnField) return
      const touch = event.touches[0]
      if (!touch) return
      const active = document.activeElement
      if (
        !shouldDismissKeyboardOnTouchMove({
          startedOnField,
          deltaY: touch.clientY - startY,
          activeTag: active?.tagName ?? null,
        })
      ) {
        return
      }
      if (active instanceof HTMLElement) active.blur()
    }

    const root = document.documentElement

    const syncKeyboard = () => {
      if (!phoneWeb()) {
        if (!isNativeIos()) {
          root.style.removeProperty("--keyboard-height")
          root.classList.remove(KEYBOARD_OPEN_CLASS)
        }
        return
      }
      const vv = window.visualViewport
      const height = vv
        ? keyboardHeightFromViewport({
            innerHeight: window.innerHeight,
            visualHeight: vv.height,
            visualOffsetTop: vv.offsetTop,
          })
        : 0
      root.style.setProperty("--keyboard-height", `${height}px`)
      root.classList.toggle(KEYBOARD_OPEN_CLASS, height > 0)
    }

    const scrollFocusedField = () => {
      if (!phoneWeb()) return
      const active = document.activeElement
      if (!(active instanceof HTMLElement)) return
      if (!active.matches(FIELD_SELECTOR)) return
      if (
        active instanceof HTMLInputElement &&
        /^(hidden|checkbox|radio|file|button|submit|range|image)$/.test(
          active.type
        )
      ) {
        return
      }
      active.scrollIntoView({ block: "nearest", inline: "nearest" })
    }

    const onFocusIn = () => {
      scrollFocusedField()
    }

    const onViewport = () => {
      syncKeyboard()
      scrollFocusedField()
    }

    document.addEventListener("touchstart", onStart, { passive: true })
    document.addEventListener("touchmove", onMove, { passive: true })
    document.addEventListener("focusin", onFocusIn)
    window.visualViewport?.addEventListener("resize", onViewport)
    window.visualViewport?.addEventListener("scroll", onViewport)
    window.addEventListener("resize", syncKeyboard)
    syncKeyboard()
    return () => {
      document.removeEventListener("touchstart", onStart)
      document.removeEventListener("touchmove", onMove)
      document.removeEventListener("focusin", onFocusIn)
      window.visualViewport?.removeEventListener("resize", onViewport)
      window.visualViewport?.removeEventListener("scroll", onViewport)
      window.removeEventListener("resize", syncKeyboard)
      if (!isNativeIos()) {
        root.style.removeProperty("--keyboard-height")
        root.classList.remove(KEYBOARD_OPEN_CLASS)
      }
    }
  }, [])

  return null
}
