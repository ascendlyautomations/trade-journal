"use client"

import { useEffect, useState } from "react"

const MAX_MD_QUERY = "(max-width: 767px)"
/** Accumulate this much downward delta before hiding. */
const HIDE_DELTA = 10
/** Accumulate this much upward delta before showing. */
const SHOW_DELTA = 8
/** Always show when near the top of the scroll root. */
const TOP_REVEAL_Y = 8

function getScrollRoot(): HTMLElement | Window {
  if (typeof document === "undefined") return window
  const el = document.querySelector("[data-tt-app-scroll]")
  if (el instanceof HTMLElement) return el
  return window
}

function readScrollY(root: HTMLElement | Window): number {
  if (root === window) {
    return window.scrollY || document.documentElement.scrollTop || 0
  }
  return (root as HTMLElement).scrollTop
}

/**
 * Mobile-only auto-hiding top navbar.
 *
 * Animates ONLY via caller-applied `transform: translateY(...)`.
 * Never mutates scroll position, padding, or chrome insets.
 */
export function useMobileAutoHideNavbar(options: {
  /** Force visible while menus / modals / popovers are open. */
  forceVisible: boolean
  /** Reset to visible on route change. */
  resetKey?: string
}) {
  const { forceVisible, resetKey } = options
  const [hidden, setHidden] = useState(false)
  const [overlayOpen, setOverlayOpen] = useState(false)

  // Suspend hide while any dialog / sheet / modal is open.
  useEffect(() => {
    if (typeof document === "undefined") return

    const check = () => {
      const open = Boolean(
        document.querySelector(
          '[aria-modal="true"], [role="dialog"][data-state="open"], [data-tt-overlay-open="true"]'
        )
      )
      setOverlayOpen(open)
    }

    check()
    const observer = new MutationObserver(check)
    observer.observe(document.body, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["aria-modal", "data-state", "data-tt-overlay-open"],
    })
    return () => observer.disconnect()
  }, [])

  const suspendHide = forceVisible || overlayOpen

  useEffect(() => {
    if (typeof window === "undefined") return

    const mq = window.matchMedia(MAX_MD_QUERY)
    let root: HTMLElement | Window = getScrollRoot()
    let lastY = 0
    let accumulated = 0
    let currentHidden = false
    let raf = 0

    const setHiddenState = (next: boolean) => {
      if (currentHidden === next) return
      currentHidden = next
      setHidden(next)
    }

    const show = () => {
      accumulated = 0
      setHiddenState(false)
    }

    const onScroll = () => {
      if (raf) return
      raf = window.requestAnimationFrame(() => {
        raf = 0

        if (!mq.matches || suspendHide) {
          lastY = readScrollY(root)
          show()
          return
        }

        const y = readScrollY(root)
        const delta = y - lastY
        lastY = y

        if (y <= TOP_REVEAL_Y) {
          show()
          return
        }

        // Ignore zero / sub-pixel noise; accumulate direction for threshold.
        if (delta === 0) return
        accumulated += delta

        if (accumulated >= HIDE_DELTA) {
          accumulated = 0
          setHiddenState(true)
        } else if (accumulated <= -SHOW_DELTA) {
          accumulated = 0
          setHiddenState(false)
        }
      })
    }

    const bind = () => {
      root = getScrollRoot()
      lastY = readScrollY(root)
      accumulated = 0
      if (root === window) {
        window.addEventListener("scroll", onScroll, { passive: true })
      } else {
        ;(root as HTMLElement).addEventListener("scroll", onScroll, {
          passive: true,
        })
      }
    }

    const unbind = () => {
      if (raf) {
        window.cancelAnimationFrame(raf)
        raf = 0
      }
      window.removeEventListener("scroll", onScroll)
      if (root instanceof HTMLElement) {
        root.removeEventListener("scroll", onScroll)
      }
    }

    const onMqChange = () => {
      unbind()
      currentHidden = false
      setHidden(false)
      accumulated = 0
      if (mq.matches) bind()
    }

    // Always start visible; never touch scroll position on mount.
    currentHidden = false
    setHidden(false)
    if (mq.matches) bind()

    mq.addEventListener("change", onMqChange)
    return () => {
      unbind()
      mq.removeEventListener("change", onMqChange)
    }
  }, [suspendHide, resetKey])

  // Menus / modals: pause hide — show immediately, no scroll writes.
  useEffect(() => {
    if (suspendHide) setHidden(false)
  }, [suspendHide])

  return suspendHide ? false : hidden
}
