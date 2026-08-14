"use client"

import { useEffect } from "react"
import { isNativeIos, isNativePlatform } from "@/lib/nativePlatform"

const NATIVE_HTML_CLASS = "tt-native"
const NATIVE_IOS_HTML_CLASS = "tt-native-ios"

/**
 * Native-shell CSS hook. Capacitor StatusBar / Keyboard plugins removed.
 * No-ops on web.
 */
export default function NativeAppShell() {
  useEffect(() => {
    if (!isNativePlatform()) return

    const root = document.documentElement
    root.classList.add(NATIVE_HTML_CLASS)
    if (isNativeIos()) root.classList.add(NATIVE_IOS_HTML_CLASS)

    return () => {
      root.classList.remove(NATIVE_HTML_CLASS)
      root.classList.remove(NATIVE_IOS_HTML_CLASS)
    }
  }, [])

  return null
}
