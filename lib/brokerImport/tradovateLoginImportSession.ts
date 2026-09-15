const SESSION_DISMISS_KEY = "tt-tradovate-import-dismissed-session"
const LOCAL_LAST_PROMPT_KEY = "tt-tradovate-import-last-prompt-ms"

/** User dismissed "Not Now" for this browser tab session. */
export function isTradovateLoginImportDismissedThisSession(): boolean {
  if (typeof sessionStorage === "undefined") return false
  return sessionStorage.getItem(SESSION_DISMISS_KEY) === "1"
}

export function markTradovateLoginImportDismissedThisSession(): void {
  if (typeof sessionStorage === "undefined") return
  sessionStorage.setItem(SESSION_DISMISS_KEY, "1")
}

/** Cross-session throttle so we do not prompt on every cold open (V1 lightweight). */
export function markTradovateLoginImportPromptShown(): void {
  if (typeof localStorage === "undefined") return
  localStorage.setItem(LOCAL_LAST_PROMPT_KEY, String(Date.now()))
}

const PROMPT_COOLDOWN_MS = 4 * 60 * 60 * 1000

export function isWithinTradovateLoginImportPromptCooldown(): boolean {
  if (typeof localStorage === "undefined") return false
  const raw = localStorage.getItem(LOCAL_LAST_PROMPT_KEY)
  if (!raw) return false
  const ms = Number(raw)
  if (!Number.isFinite(ms)) return false
  return Date.now() - ms < PROMPT_COOLDOWN_MS
}

export function isTradovateLoginImportPromptPath(pathname: string): boolean {
  if (!pathname) return false
  if (pathname.startsWith("/login") || pathname.startsWith("/onboarding")) return false
  if (pathname.startsWith("/auth")) return false
  if (pathname.startsWith("/settings/integrations/tradovate")) return false
  return (
    pathname === "/dashboard" ||
    pathname.startsWith("/app") ||
    pathname === "/trades" ||
    pathname.startsWith("/trades/")
  )
}
