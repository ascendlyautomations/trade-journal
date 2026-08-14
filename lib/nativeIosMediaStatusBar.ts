import { isNativeIos } from "./nativePlatform"

/**
 * Hide / restore status bar around media viewer.
 * Capacitor StatusBar plugin removed — CSS safe areas remain.
 */

export async function hideNativeIosMediaStatusBar(): Promise<void> {
  if (typeof window === "undefined" || !isNativeIos()) return
}

export async function restoreNativeIosMediaStatusBar(): Promise<void> {
  if (typeof window === "undefined" || !isNativeIos()) return
}
