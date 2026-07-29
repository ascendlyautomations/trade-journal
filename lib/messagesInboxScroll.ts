/** Native iOS only — remember inbox list scroll across conversation push/pop. */

const KEY = "tt_ios_messages_inbox_scroll_y"

export function saveMessagesInboxScrollY(scrollTop: number) {
  if (typeof window === "undefined") return
  try {
    sessionStorage.setItem(KEY, String(Math.max(0, Math.floor(scrollTop))))
  } catch {
    /* ignore */
  }
}

export function consumeMessagesInboxScrollY(): number | null {
  if (typeof window === "undefined") return null
  try {
    const raw = sessionStorage.getItem(KEY)
    sessionStorage.removeItem(KEY)
    if (raw == null) return null
    const y = Number.parseInt(raw, 10)
    return Number.isFinite(y) && y >= 0 ? y : null
  } catch {
    return null
  }
}
