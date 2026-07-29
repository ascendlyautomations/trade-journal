"use client"

import { useEffect } from "react"
import { isNativeIos, isNativePlatform } from "@/lib/nativePlatform"
import { installNativeImagePicker } from "@/lib/imagePicker"

const NATIVE_HTML_CLASS = "tt-native"
const NATIVE_IOS_HTML_CLASS = "tt-native-ios"

/**
 * Native-only chrome: status bar, keyboard, shell CSS hook, and image picker.
 * Applies once at the document root so every route inherits the same behavior.
 * No-ops on web.
 */
export default function NativeAppShell() {
  useEffect(() => {
    if (!isNativePlatform()) return

    const root = document.documentElement
    root.classList.add(NATIVE_HTML_CLASS)
    if (isNativeIos()) root.classList.add(NATIVE_IOS_HTML_CLASS)

    let cancelled = false

    void (async () => {
      try {
        const { StatusBar, Style } = await import("@capacitor/status-bar")
        if (cancelled) return
        // Edge-to-edge WebView — one continuous paint surface (no StatusBar
        // backgroundView strip above the WKWebView). Chrome uses CSS safe-area.
        await StatusBar.setOverlaysWebView({ overlay: true })
        await StatusBar.setBackgroundColor({ color: "#0b1f3a" })
        await StatusBar.setStyle({ style: Style.Dark })
      } catch {
        // Plugin unavailable — CSS safe-area floors still apply.
      }

      try {
        const { Keyboard, KeyboardResize, KeyboardStyle } = await import(
          "@capacitor/keyboard"
        )
        if (cancelled) return
        // Reinforce capacitor.config (covers hot reload / older synced builds).
        await Keyboard.setResizeMode({ mode: KeyboardResize.Body })
        await Keyboard.setStyle({ style: KeyboardStyle.Dark })
      } catch {
        // Keyboard plugin unavailable — iOS default resize still works.
      }
    })()

    // Take Photo / Choose From Library sheet for all image uploads.
    const uninstallImagePicker = installNativeImagePicker()

    return () => {
      cancelled = true
      root.classList.remove(NATIVE_HTML_CLASS)
      root.classList.remove(NATIVE_IOS_HTML_CLASS)
      uninstallImagePicker()
    }
  }, [])

  return null
}
