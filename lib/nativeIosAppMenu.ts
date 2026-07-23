/**
 * Tiny bridge so the iOS bottom-tab "More" control opens the existing
 * Navbar hamburger menu — same panel, same items, no duplicate menu.
 */

export const NATIVE_IOS_OPEN_APP_MENU_EVENT = "tt:native-ios-open-app-menu"

export function openNativeIosAppMenu() {
  if (typeof window === "undefined") return
  void import("@/lib/nativeHaptics").then(({ hapticLight }) => {
    hapticLight("menu")
  })
  window.dispatchEvent(new Event(NATIVE_IOS_OPEN_APP_MENU_EVENT))
}
