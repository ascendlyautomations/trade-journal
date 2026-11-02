/** Phone web only. Desktop (≥768) and native iOS must not take this path. */
export const MOBILE_WEB_TOUCH_MEDIA = "(max-width: 767px)"

export const MOBILE_WEB_SHEET_DISMISS_PX = 72

export const MOBILE_WEB_KEYBOARD_DISMISS_PX = 12

const TEXT_FIELD_TAGS = new Set(["INPUT", "TEXTAREA", "SELECT"])

export function isPhoneWebTouchTarget(): boolean {
  if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
    return false
  }
  if (typeof document === "undefined") return false
  if (document.documentElement.classList?.contains("tt-native-ios")) return false
  return window.matchMedia(MOBILE_WEB_TOUCH_MEDIA).matches
}

/**
 * Header drag-down dismisses a bottom sheet.
 * Mostly-horizontal moves are left to the browser (back swipe) and to scroll.
 */
export function shouldDismissSheetFromVerticalDrag(
  startX: number | null,
  startY: number | null,
  endX: number | null,
  endY: number | null
): boolean {
  if (startY == null || endY == null) return false
  const dy = endY - startY
  if (dy < MOBILE_WEB_SHEET_DISMISS_PX) return false
  if (startX != null && endX != null && Math.abs(endX - startX) > dy) return false
  return true
}

/** Scroll the page, not the field, to dismiss the keyboard. */
export function shouldDismissKeyboardOnTouchMove(input: {
  startedOnField: boolean
  deltaY: number
  activeTag: string | null
}): boolean {
  if (input.startedOnField) return false
  if (Math.abs(input.deltaY) < MOBILE_WEB_KEYBOARD_DISMISS_PX) return false
  if (!input.activeTag) return false
  return TEXT_FIELD_TAGS.has(input.activeTag)
}
