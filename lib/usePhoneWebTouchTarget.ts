"use client"

import { useEffect, useState } from "react"
import { isPhoneWebTouchTarget, MOBILE_WEB_TOUCH_MEDIA } from "./mobileWebTouch"

export function usePhoneWebTouchTarget(): boolean {
  const [matches, setMatches] = useState(false)

  useEffect(() => {
    if (typeof window === "undefined") return
    const mq = window.matchMedia(MOBILE_WEB_TOUCH_MEDIA)
    const sync = () => setMatches(isPhoneWebTouchTarget())
    sync()
    mq.addEventListener("change", sync)
    return () => mq.removeEventListener("change", sync)
  }, [])

  return matches
}
