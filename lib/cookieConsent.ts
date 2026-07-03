/** Persisted cookie consent — extensible for future analytics categories. */

export const COOKIE_CONSENT_STORAGE_KEY = "tradetraxs_cookie_consent_v1"

export type CookieConsentChoice = "all" | "essential"

export type CookieConsentRecord = {
  version: 1
  choice: CookieConsentChoice
  /** Always true — essential cookies/storage required for the service. */
  essential: true
  /** Product analytics (e.g. Vercel Analytics). False when user chooses essential only. */
  analytics: boolean
  updatedAt: string
}

function parseRecord(raw: string): CookieConsentRecord | null {
  try {
    const parsed = JSON.parse(raw) as Partial<CookieConsentRecord>
    if (parsed.version !== 1) return null
    if (parsed.choice !== "all" && parsed.choice !== "essential") return null
    if (parsed.essential !== true) return null
    if (typeof parsed.analytics !== "boolean") return null
    if (typeof parsed.updatedAt !== "string" || !parsed.updatedAt.trim()) return null
    return parsed as CookieConsentRecord
  } catch {
    return null
  }
}

export function readCookieConsent(): CookieConsentRecord | null {
  if (typeof window === "undefined") return null
  const raw = window.localStorage.getItem(COOKIE_CONSENT_STORAGE_KEY)
  if (!raw) return null
  return parseRecord(raw)
}

export function hasCookieConsentChoice(): boolean {
  return readCookieConsent() != null
}

export function saveCookieConsent(choice: CookieConsentChoice): CookieConsentRecord {
  const record: CookieConsentRecord = {
    version: 1,
    choice,
    essential: true,
    analytics: choice === "all",
    updatedAt: new Date().toISOString(),
  }
  if (typeof window !== "undefined") {
    window.localStorage.setItem(COOKIE_CONSENT_STORAGE_KEY, JSON.stringify(record))
  }
  return record
}

export function clearCookieConsent(): void {
  if (typeof window === "undefined") return
  window.localStorage.removeItem(COOKIE_CONSENT_STORAGE_KEY)
}

export function isAnalyticsAllowed(): boolean {
  const record = readCookieConsent()
  if (!record) return false
  return record.analytics
}
