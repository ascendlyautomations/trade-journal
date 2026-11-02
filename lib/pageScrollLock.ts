let lockCount = 0
let savedHtmlOverflow = ""
let savedBodyOverflow = ""
let savedScrollY = 0
let appliedPhoneWebFixedLock = false

function getScrollElements() {
  if (typeof document === "undefined") return null
  return {
    html: document.documentElement,
    body: document.body,
  }
}

/**
 * iOS Safari ignores overflow:hidden on the document. Phone web pins the body
 * so sheets and modals do not scroll the page behind them.
 * Desktop and native iOS keep the overflow-only lock.
 */
function shouldPinPhoneWebBody(): boolean {
  if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
    return false
  }
  const root = document.documentElement
  if (root.classList?.contains("tt-native-ios")) return false
  return window.matchMedia("(max-width: 767px)").matches
}

function clearPhoneWebFixedLock(body: HTMLElement) {
  body.style.position = ""
  body.style.top = ""
  body.style.left = ""
  body.style.right = ""
  body.style.width = ""
}

/** Acquire a page scroll lock. Pair every call with `unlockPageScroll()`. */
export function lockPageScroll(): void {
  const els = getScrollElements()
  if (!els) return

  if (lockCount === 0) {
    savedHtmlOverflow = els.html.style.overflow
    savedBodyOverflow = els.body.style.overflow
    els.html.style.overflow = "hidden"
    els.body.style.overflow = "hidden"
    if (shouldPinPhoneWebBody()) {
      appliedPhoneWebFixedLock = true
      savedScrollY = window.scrollY || els.html.scrollTop || 0
      els.body.style.position = "fixed"
      els.body.style.top = `-${savedScrollY}px`
      els.body.style.left = "0"
      els.body.style.right = "0"
      els.body.style.width = "100%"
    }
  }
  lockCount++
}

/** Release a page scroll lock acquired via `lockPageScroll()`. */
export function unlockPageScroll(): void {
  const els = getScrollElements()
  if (!els) return

  if (lockCount <= 0) {
    lockCount = 0
    return
  }

  lockCount--
  if (lockCount === 0) {
    els.html.style.overflow = savedHtmlOverflow
    els.body.style.overflow = savedBodyOverflow
    if (appliedPhoneWebFixedLock) {
      appliedPhoneWebFixedLock = false
      clearPhoneWebFixedLock(els.body)
      const y = savedScrollY
      savedScrollY = 0
      if (typeof window.scrollTo === "function") {
        window.scrollTo(0, y)
      }
    }
  }
}

/** Clear all locks after route changes or error recovery. */
export function resetPageScrollLock(): void {
  const els = getScrollElements()
  const wasPinned = appliedPhoneWebFixedLock
  lockCount = 0
  appliedPhoneWebFixedLock = false
  savedScrollY = 0
  if (!els) return
  els.html.style.overflow = ""
  els.body.style.overflow = ""
  if (wasPinned) clearPhoneWebFixedLock(els.body)
}
