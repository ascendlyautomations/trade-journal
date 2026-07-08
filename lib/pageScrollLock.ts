let lockCount = 0
let savedHtmlOverflow = ""
let savedBodyOverflow = ""

function getScrollElements() {
  if (typeof document === "undefined") return null
  return {
    html: document.documentElement,
    body: document.body,
  }
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
  }
}

/** Clear all locks after route changes or error recovery. */
export function resetPageScrollLock(): void {
  const els = getScrollElements()
  lockCount = 0
  if (!els) return
  els.html.style.overflow = ""
  els.body.style.overflow = ""
}
