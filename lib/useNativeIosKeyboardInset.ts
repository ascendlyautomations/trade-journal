"use client"

import { useEffect, useRef } from "react"
import { isNativeIos } from "@/lib/nativePlatform"

const KEYBOARD_HEIGHT_VAR = "--keyboard-height"

export type NativeIosKeyboardInsetOptions = {
  /**
   * DocumentElement class while the inset is active (e.g. tt-ios-dm).
   * Cleared on unmount.
   */
  htmlClass?: string
  /** Called when the keyboard finishes opening (after height is applied). */
  onKeyboardShow?: () => void
}

/**
 * Keyboard inset via visualViewport (Capacitor Keyboard plugin removed).
 * No-ops when not in the native iOS shell markers.
 */
export function useNativeIosKeyboardInset(
  enabled: boolean,
  options: NativeIosKeyboardInsetOptions = {}
) {
  const { htmlClass, onKeyboardShow } = options
  const onKeyboardShowRef = useRef(onKeyboardShow)
  onKeyboardShowRef.current = onKeyboardShow

  useEffect(() => {
    if (!enabled || !isNativeIos()) return

    const root = document.documentElement
    if (htmlClass) root.classList.add(htmlClass)
    root.style.setProperty(KEYBOARD_HEIGHT_VAR, "0px")

    const vv = window.visualViewport
    if (!vv) {
      return () => {
        if (htmlClass) root.classList.remove(htmlClass)
        root.style.removeProperty(KEYBOARD_HEIGHT_VAR)
      }
    }

    const sync = () => {
      const covered = Math.max(0, window.innerHeight - vv.height - vv.offsetTop)
      root.style.setProperty(KEYBOARD_HEIGHT_VAR, `${covered}px`)
      if (covered > 0) onKeyboardShowRef.current?.()
    }
    vv.addEventListener("resize", sync)
    vv.addEventListener("scroll", sync)
    sync()

    return () => {
      vv.removeEventListener("resize", sync)
      vv.removeEventListener("scroll", sync)
      if (htmlClass) root.classList.remove(htmlClass)
      root.style.removeProperty(KEYBOARD_HEIGHT_VAR)
    }
  }, [enabled, htmlClass])
}
