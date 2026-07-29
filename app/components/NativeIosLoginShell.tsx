"use client"

import {
  useEffect,
  useLayoutEffect,
  useState,
  type PointerEvent,
  type ReactNode,
} from "react"
import { isNativeIos } from "@/lib/nativePlatform"

const IOS_AUTH_HTML_CLASS = "tt-ios-auth"
const KEYBOARD_HEIGHT_VAR = "--keyboard-height"

function isInteractiveTarget(target: EventTarget | null): boolean {
  if (!(target instanceof Element)) return false
  return Boolean(
    target.closest(
      "input, textarea, select, button, a, label, [role='tablist'], [role='tab'], [contenteditable='true']"
    )
  )
}

async function dismissKeyboard() {
  const active = document.activeElement
  if (active instanceof HTMLElement) active.blur()
  try {
    const { Keyboard } = await import("@capacitor/keyboard")
    await Keyboard.hide()
  } catch {
    // Plugin unavailable — blur alone is enough on web.
  }
}

function scrollFocusedFieldIntoView() {
  const active = document.activeElement
  if (!(active instanceof HTMLElement)) return
  if (active.tagName !== "INPUT" && active.tagName !== "TEXTAREA") return
  window.requestAnimationFrame(() => {
    active.scrollIntoView({
      block: "center",
      inline: "nearest",
      behavior: "smooth",
    })
  })
}

type NativeIosLoginShellProps = {
  /** SSR/cookie-derived flag — must match first client render to avoid hydration mismatch. */
  initialNativeIos?: boolean
  children: (nativeIos: boolean) => ReactNode
}

/**
 * Login-only iOS Capacitor chrome:
 * - Viewport-locked scroll region (no min-h-screen jump)
 * - Keyboard resize None while mounted (avoids body-height thrash)
 * - Bottom inset tracks keyboard height
 * - Tap outside fields dismisses the keyboard
 * No layout changes on web / Android (nativeIos === false).
 */
export default function NativeIosLoginShell({
  initialNativeIos = false,
  children,
}: NativeIosLoginShellProps) {
  const [nativeIos, setNativeIos] = useState(initialNativeIos)

  useLayoutEffect(() => {
    const next = initialNativeIos || isNativeIos()
    setNativeIos(next)
    if (!next) return
    document.documentElement.classList.add(IOS_AUTH_HTML_CLASS)
    document.documentElement.style.setProperty(KEYBOARD_HEIGHT_VAR, "0px")
  }, [initialNativeIos])

  useEffect(() => {
    if (!nativeIos) return

    const root = document.documentElement
    root.classList.add(IOS_AUTH_HTML_CLASS)
    root.style.setProperty(KEYBOARD_HEIGHT_VAR, "0px")

    let cancelled = false
    const removals: Array<() => void> = []

    void (async () => {
      try {
        const { Keyboard, KeyboardResize } = await import("@capacitor/keyboard")
        if (cancelled) return

        // Body resize shrinks <body> and fights centered min-h-screen layouts.
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
            scrollFocusedFieldIntoView()
          }
        )
        const didShowSub = await Keyboard.addListener(
          "keyboardDidShow",
          () => {
            scrollFocusedFieldIntoView()
          }
        )
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
          if (covered > 0) scrollFocusedFieldIntoView()
        }
        vv.addEventListener("resize", sync)
        vv.addEventListener("scroll", sync)
        removals.push(() => {
          vv.removeEventListener("resize", sync)
          vv.removeEventListener("scroll", sync)
        })
      }
    })()

    function onFocusIn(e: FocusEvent) {
      const t = e.target
      if (!(t instanceof HTMLElement)) return
      if (t.tagName === "INPUT" || t.tagName === "TEXTAREA") {
        scrollFocusedFieldIntoView()
      }
    }
    document.addEventListener("focusin", onFocusIn)
    removals.push(() => document.removeEventListener("focusin", onFocusIn))

    return () => {
      cancelled = true
      for (const remove of removals) remove()
      root.classList.remove(IOS_AUTH_HTML_CLASS)
      root.style.removeProperty(KEYBOARD_HEIGHT_VAR)
    }
  }, [nativeIos])

  function handlePointerDown(e: PointerEvent<HTMLDivElement>) {
    if (!nativeIos) return
    if (isInteractiveTarget(e.target)) return
    void dismissKeyboard()
  }

  return (
    <div
      className={
        nativeIos
          ? "relative flex h-[100dvh] max-h-[100dvh] flex-col overflow-x-hidden overflow-y-auto overscroll-y-contain bg-[#0b1f3a] text-white [-webkit-overflow-scrolling:touch]"
          : "relative flex min-h-screen items-center justify-center text-white"
      }
      onPointerDown={handlePointerDown}
    >
      {children(nativeIos)}
    </div>
  )
}
