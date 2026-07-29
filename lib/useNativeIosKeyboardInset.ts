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
 * Capacitor iOS only: KeyboardResize.None + --keyboard-height from plugin events.
 * Restores KeyboardResize.Body on cleanup. No-ops on web / Android.
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

    let cancelled = false
    const removals: Array<() => void> = []

    void (async () => {
      try {
        const { Keyboard, KeyboardResize } = await import("@capacitor/keyboard")
        if (cancelled) return

        await Keyboard.setResizeMode({ mode: KeyboardResize.None })
        await Keyboard.setScroll({ isDisabled: false })
        await Keyboard.setAccessoryBarVisible({ isVisible: true })

        const showSub = await Keyboard.addListener(
          "keyboardWillShow",
          (info) => {
            root.style.setProperty(
              KEYBOARD_HEIGHT_VAR,
              `${Math.max(0, info.keyboardHeight)}px`
            )
            onKeyboardShowRef.current?.()
          }
        )
        const didShowSub = await Keyboard.addListener("keyboardDidShow", () => {
          onKeyboardShowRef.current?.()
        })
        const hideSub = await Keyboard.addListener("keyboardWillHide", () => {
          root.style.setProperty(KEYBOARD_HEIGHT_VAR, "0px")
        })

        removals.push(() => {
          void showSub.remove()
          void didShowSub.remove()
          void hideSub.remove()
        })
        removals.push(() => {
          void Keyboard.setResizeMode({ mode: KeyboardResize.Body }).catch(
            () => {}
          )
        })
      } catch {
        const vv = window.visualViewport
        if (!vv) return
        const sync = () => {
          const covered = Math.max(
            0,
            window.innerHeight - vv.height - vv.offsetTop
          )
          root.style.setProperty(KEYBOARD_HEIGHT_VAR, `${covered}px`)
          if (covered > 0) onKeyboardShowRef.current?.()
        }
        vv.addEventListener("resize", sync)
        vv.addEventListener("scroll", sync)
        removals.push(() => {
          vv.removeEventListener("resize", sync)
          vv.removeEventListener("scroll", sync)
        })
      }
    })()

    return () => {
      cancelled = true
      for (const remove of removals) remove()
      if (htmlClass) root.classList.remove(htmlClass)
      root.style.removeProperty(KEYBOARD_HEIGHT_VAR)
    }
  }, [enabled, htmlClass])
}
