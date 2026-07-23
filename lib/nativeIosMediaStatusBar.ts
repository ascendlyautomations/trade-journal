import { isNativeIos } from "./nativePlatform"

/**
 * Hide / restore the Capacitor status bar around the native iOS media viewer.
 * Web, Android, and desktop are no-ops.
 */

let hideCount = 0

export async function hideNativeIosMediaStatusBar(): Promise<void> {
  if (typeof window === "undefined" || !isNativeIos()) return
  hideCount += 1
  if (hideCount > 1) return
  try {
    const { StatusBar } = await import("@capacitor/status-bar")
    await StatusBar.setOverlaysWebView({ overlay: true })
    await StatusBar.hide()
  } catch {
    // Plugin unavailable — viewer still works with CSS safe areas.
  }
}

export async function restoreNativeIosMediaStatusBar(): Promise<void> {
  if (typeof window === "undefined" || !isNativeIos()) return
  hideCount = Math.max(0, hideCount - 1)
  if (hideCount > 0) return
  try {
    const { StatusBar, Style } = await import("@capacitor/status-bar")
    await StatusBar.show()
    await StatusBar.setOverlaysWebView({ overlay: false })
    await StatusBar.setBackgroundColor({ color: "#0b1f3a" })
    await StatusBar.setStyle({ style: Style.Dark })
  } catch {
    // Plugin unavailable.
  }
}
