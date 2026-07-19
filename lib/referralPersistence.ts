import { isBetaReferralRef } from "./betaReferralCode.ts"

/** localStorage key used across signup, checkout, and OAuth flows. */
export const REFERRAL_CODE_STORAGE_KEY = "referral_code"

/** Browser-only TTL. Does not affect auth metadata or database attribution. */
export const REFERRAL_STORAGE_MAX_AGE_MS = 30 * 24 * 60 * 60 * 1000

export type StoredReferralRecord = {
  v: 1
  code: string
  storedAt: number
}

function isStoredReferralRecord(value: unknown): value is StoredReferralRecord {
  if (!value || typeof value !== "object") return false
  const row = value as Record<string, unknown>
  return (
    row.v === 1 &&
    typeof row.code === "string" &&
    typeof row.storedAt === "number" &&
    Number.isFinite(row.storedAt)
  )
}

/**
 * Parse a localStorage value into a referral record.
 * Legacy bare strings are accepted as a one-time migration shape (no timestamp).
 */
export function parseStoredReferralValue(
  raw: string | null | undefined
):
  | { kind: "record"; record: StoredReferralRecord }
  | { kind: "legacy"; code: string }
  | { kind: "empty" } {
  if (raw == null) return { kind: "empty" }
  const trimmed = raw.trim()
  if (!trimmed) return { kind: "empty" }

  if (trimmed.startsWith("{")) {
    try {
      const parsed: unknown = JSON.parse(trimmed)
      if (isStoredReferralRecord(parsed)) {
        const code = parsed.code.trim()
        if (!code) return { kind: "empty" }
        return {
          kind: "record",
          record: { v: 1, code, storedAt: parsed.storedAt },
        }
      }
    } catch {
      /* fall through to legacy / empty */
    }
  }

  return { kind: "legacy", code: trimmed }
}

export function isStoredReferralExpired(
  storedAt: number,
  nowMs = Date.now(),
  maxAgeMs = REFERRAL_STORAGE_MAX_AGE_MS
): boolean {
  if (!Number.isFinite(storedAt) || storedAt <= 0) return true
  return nowMs - storedAt > maxAgeMs
}

function writeReferralRecord(code: string, storedAt = Date.now()): void {
  if (typeof window === "undefined") return
  const record: StoredReferralRecord = {
    v: 1,
    code,
    storedAt,
  }
  try {
    localStorage.setItem(REFERRAL_CODE_STORAGE_KEY, JSON.stringify(record))
  } catch {
    /* ignore quota / private mode */
  }
}

/** Persist `?ref=` from the current or provided query string. Returns stored value. */
export function persistReferralCodeFromUrl(search?: string): string | null {
  if (typeof window === "undefined") return null

  const query = search ?? window.location.search
  const ref = new URLSearchParams(query).get("ref")
  const trimmed = ref?.trim()
  if (!trimmed) return null

  // Closed beta invite — do not persist or attribute as a referral.
  if (isBetaReferralRef(trimmed)) {
    clearStoredReferralCode()
    return null
  }

  writeReferralRecord(trimmed)
  return trimmed
}

/**
 * Read the browser-persisted referral code, discarding expired or beta values.
 * Expired / invalid entries are removed from localStorage only — never from
 * auth metadata or the database.
 */
export function readStoredReferralCode(nowMs = Date.now()): string | null {
  if (typeof window === "undefined") return null
  try {
    const raw = localStorage.getItem(REFERRAL_CODE_STORAGE_KEY)
    const parsed = parseStoredReferralValue(raw)

    if (parsed.kind === "empty") return null

    if (parsed.kind === "legacy") {
      if (isBetaReferralRef(parsed.code)) {
        clearStoredReferralCode()
        return null
      }
      // One-time migrate bare strings so the TTL starts from first modern read.
      // Mid-signup / in-flight OAuth still works; weeks-old bare values get a
      // fresh window once, then expire normally.
      writeReferralRecord(parsed.code, nowMs)
      return parsed.code
    }

    const { code, storedAt } = parsed.record
    if (isBetaReferralRef(code)) {
      clearStoredReferralCode()
      return null
    }
    if (isStoredReferralExpired(storedAt, nowMs)) {
      clearStoredReferralCode()
      return null
    }
    return code
  } catch {
    return null
  }
}

/**
 * Clear browser referral state after successful attribution or after the
 * referral has been safely persisted to auth metadata / the profile.
 * Never call this before attribution (or metadata persistence) succeeds.
 */
export function clearStoredReferralCode(): void {
  if (typeof window === "undefined") return
  try {
    localStorage.removeItem(REFERRAL_CODE_STORAGE_KEY)
  } catch {
    /* ignore */
  }
}
