/** Mobile web room conversation that embeds session chrome above the composer. */
let embeddedRoomId: string | null = null
let bottomInsetPx = 0
const listeners = new Set<() => void>()

function notify() {
  listeners.forEach((l) => l())
}

export function subscribeTradeRoomMobileSessionChrome(listener: () => void) {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

export function getTradeRoomMobileSessionChromeEmbeddedRoomId(): string | null {
  return embeddedRoomId
}

export function setTradeRoomMobileSessionChromeEmbedded(roomId: string | null) {
  const next = roomId?.trim() || null
  if (embeddedRoomId === next) return
  embeddedRoomId = next
  notify()
}

/** Height of the fixed tab-shell session chrome (mobile web). */
export function getTradeRoomMobileSessionChromeBottomInset(): number {
  return bottomInsetPx
}

export function setTradeRoomMobileSessionChromeBottomInset(px: number) {
  const next = Math.max(0, Math.round(px))
  if (bottomInsetPx === next) return
  bottomInsetPx = next
  if (typeof document !== "undefined") {
    document.documentElement.style.setProperty(
      "--app-live-session-chrome-offset",
      `${next}px`
    )
    document.documentElement.classList.toggle(
      "tt-mobile-web-live-session-chrome",
      next > 0
    )
  }
  notify()
}

/** @deprecated use subscribeTradeRoomMobileSessionChrome */
export const subscribeTradeRoomMobileSessionChromeEmbedded =
  subscribeTradeRoomMobileSessionChrome
