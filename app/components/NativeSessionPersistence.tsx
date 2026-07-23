"use client"

import { useEffect, useRef } from "react"
import { usePathname, useSearchParams } from "next/navigation"
import { isNativePlatform } from "@/lib/nativePlatform"

const SCROLL_KEY = "tt_native_scroll_v1"
const PATH_KEY = "tt_native_path_v1"

type ScrollMap = Record<string, number>

function readScrollMap(): ScrollMap {
  try {
    const raw = sessionStorage.getItem(SCROLL_KEY)
    if (!raw) return {}
    const parsed = JSON.parse(raw) as unknown
    return parsed && typeof parsed === "object" ? (parsed as ScrollMap) : {}
  } catch {
    return {}
  }
}

function writeScrollMap(map: ScrollMap) {
  try {
    sessionStorage.setItem(SCROLL_KEY, JSON.stringify(map))
  } catch {
    // Quota / private mode — persistence is best-effort.
  }
}

function pathKey(pathname: string, search: string) {
  return `${pathname}${search}`
}

/**
 * Native-only: persist route + scroll across WKWebView remounts.
 * Does NOT reload, refresh, or re-route on resume/appStateChange.
 */
export default function NativeSessionPersistence() {
  const pathname = usePathname()
  const searchParams = useSearchParams()
  const search = searchParams?.toString() ? `?${searchParams.toString()}` : ""
  const key = pathKey(pathname || "/", search)
  const restoredForKey = useRef<string | null>(null)

  useEffect(() => {
    if (!isNativePlatform()) return

    try {
      sessionStorage.setItem(PATH_KEY, key)
    } catch {
      // ignore
    }

    // Restore scroll once per path after paint (WKWebView remount recovery).
    if (restoredForKey.current === key) return
    const y = readScrollMap()[key]
    if (typeof y === "number" && y > 0) {
      restoredForKey.current = key
      requestAnimationFrame(() => {
        window.scrollTo({ top: y, left: 0, behavior: "auto" })
      })
    } else {
      restoredForKey.current = key
    }
  }, [key])

  useEffect(() => {
    if (!isNativePlatform()) return

    let throttleTimer: number | null = null
    const persistScroll = () => {
      const map = readScrollMap()
      map[key] = window.scrollY || 0
      writeScrollMap(map)
    }

    const onScroll = () => {
      if (throttleTimer != null) return
      throttleTimer = window.setTimeout(() => {
        throttleTimer = null
        persistScroll()
      }, 200)
    }

    // Persist on backgrounding markers — never reload.
    const onVisibility = () => {
      if (document.visibilityState === "hidden") persistScroll()
    }
    const onPageHide = () => persistScroll()

    window.addEventListener("scroll", onScroll, { passive: true })
    document.addEventListener("visibilitychange", onVisibility)
    window.addEventListener("pagehide", onPageHide)

    let removeAppListener: (() => void) | undefined
    void import("@capacitor/app")
      .then(({ App }) =>
        App.addListener("appStateChange", ({ isActive }) => {
          if (!isActive) persistScroll()
          // Intentionally no reload / router.refresh when becoming active.
        })
      )
      .then((handle) => {
        removeAppListener = () => {
          void handle.remove()
        }
      })
      .catch(() => {
        // Plugin unavailable — web/visibility listeners still persist scroll.
      })

    return () => {
      if (throttleTimer != null) window.clearTimeout(throttleTimer)
      persistScroll()
      window.removeEventListener("scroll", onScroll)
      document.removeEventListener("visibilitychange", onVisibility)
      window.removeEventListener("pagehide", onPageHide)
      removeAppListener?.()
    }
  }, [key])

  return null
}
