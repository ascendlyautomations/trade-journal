/**
 * Central registry: map internal error codes → polished user-facing copy.
 * Add new mappings here only — do not scatter conditionals across the app.
 */
export const USER_FACING_ERROR_MESSAGES = {
  FREE_PLAN_DAILY_POST_LIMIT:
    "Free accounts can create 1 post every 24 hours. Upgrade to Pro for unlimited posting.",
  FREE_PLAN_DAILY_TRADE_LIMIT:
    "Free accounts can create up to 3 trades every 24 hours. Upgrade to Pro for unlimited trades.",
  FREE_PLAN_REELS_LIMIT:
    "Free accounts can upload 1 reel every 24 hours. Upgrade to Pro for unlimited reels.",
  FREE_PLAN_ACCOUNT_LIMIT:
    "Free plan allows up to 3 accounts. Upgrade to Pro for unlimited accounts.",
  RATE_LIMIT_EXCEEDED:
    "You're doing that too often. Please wait a moment and try again.",
  UNAUTHORIZED:
    "You don't have permission to perform this action.",
  FILE_TOO_LARGE: "This file is too large.",
  NETWORK_ERROR:
    "Unable to reach the server. Please check your connection and try again.",
  UNKNOWN_ERROR: "Something went wrong. Please try again.",
} as const

export type UserFacingErrorCode = keyof typeof USER_FACING_ERROR_MESSAGES

export const UNKNOWN_ERROR_MESSAGE = USER_FACING_ERROR_MESSAGES.UNKNOWN_ERROR

type ErrorShape = {
  message?: string
  code?: string
  hint?: string
  details?: string
  name?: string
}

function isBarePostgresCode(text: string): boolean {
  return /^p\d{4}$/i.test(text.trim())
}

function isPostgrestCode(text: string): boolean {
  return /^pgrst\d+$/i.test(text.trim())
}

/** ALL_CAPS internal constants (e.g. FREE_PLAN_DAILY_POST_LIMIT). */
function isInternalConstant(text: string): boolean {
  const trimmed = text.trim()
  if (/^[A-Z][A-Z0-9_]*$/.test(trimmed)) return true
  const head = trimmed.split(":")[0]?.trim() ?? ""
  return /^[A-Z][A-Z0-9_]*$/.test(head) && head.length > 2
}

function looksLikeStackTrace(text: string): boolean {
  return /\n\s+at\s+/m.test(text) || /\.tsx?:\d+/.test(text)
}

/** Sentences from Postgres `raise exception '...'` or hints — show as-is. */
function isHumanReadableSentence(text: string): boolean {
  const t = text.trim()
  if (!t || t.length < 4) return false
  if (isInternalConstant(t)) return false
  if (isBarePostgresCode(t) || isPostgrestCode(t)) return false
  if (looksLikeStackTrace(t)) return false
  return /[a-z]/.test(t)
}

function lookupMappedMessage(text: string): string | null {
  const trimmed = text.trim()
  const upper = trimmed.toUpperCase()

  if (upper in USER_FACING_ERROR_MESSAGES) {
    return USER_FACING_ERROR_MESSAGES[upper as UserFacingErrorCode]
  }

  const head = trimmed.split(":")[0]?.trim().toUpperCase() ?? ""
  if (head && head in USER_FACING_ERROR_MESSAGES) {
    return USER_FACING_ERROR_MESSAGES[head as UserFacingErrorCode]
  }

  const lower = trimmed.toLowerCase()
  if (lower.includes("rate_limit_exceeded")) {
    return USER_FACING_ERROR_MESSAGES.RATE_LIMIT_EXCEEDED
  }

  if (
    lower.includes("too large") ||
    lower.includes("entity too large") ||
    lower.includes("file size limit") ||
    lower.includes("payload too large")
  ) {
    return USER_FACING_ERROR_MESSAGES.FILE_TOO_LARGE
  }

  if (
    lower.includes("row-level security") ||
    lower.includes("permission denied") ||
    lower.includes("not authorized") ||
    lower === "unauthorized"
  ) {
    return USER_FACING_ERROR_MESSAGES.UNAUTHORIZED
  }

  if (
    lower.includes("failed to fetch") ||
    lower.includes("networkerror") ||
    lower.includes("network request failed") ||
    lower.includes("load failed")
  ) {
    return USER_FACING_ERROR_MESSAGES.NETWORK_ERROR
  }

  return null
}

function resolveTextCandidate(text: string | null | undefined): string | null {
  if (!text?.trim()) return null
  const trimmed = text.trim()

  const mapped = lookupMappedMessage(trimmed)
  if (mapped) return mapped

  if (isHumanReadableSentence(trimmed)) return trimmed

  return null
}

/** Collect raw strings from common error shapes (Supabase, Error, string). */
export function extractErrorCandidates(error: unknown): string[] {
  if (error == null) return []

  if (typeof error === "string") {
    return [error]
  }

  const e = error as ErrorShape
  const candidates: string[] = []

  if (e.message) candidates.push(e.message)
  if (e.hint) candidates.push(e.hint)
  if (e.details) candidates.push(e.details)

  if (
    e.code &&
    !isBarePostgresCode(e.code) &&
    !isPostgrestCode(e.code)
  ) {
    candidates.push(e.code)
  }

  return candidates
}

/** @deprecated Prefer {@link extractErrorCandidates}. */
export function extractSupabaseErrorMessage(error: unknown): string | null {
  for (const candidate of extractErrorCandidates(error)) {
    const resolved = resolveTextCandidate(candidate)
    if (resolved) return resolved
  }
  return null
}

/** Log the original error in development; never shown to users. */
export function logErrorForDevelopers(context: string, error: unknown): void {
  if (process.env.NODE_ENV === "production") return
  console.error(`[userFacingError] ${context}`, error)
}

/**
 * Convert any thrown/returned error into safe, user-facing copy.
 * - Internal ALL_CAPS codes → mapped messages
 * - Human-readable DB sentences → passed through
 * - Technical-only payloads → generic fallback
 */
export function toUserFacingErrorMessage(error: unknown): string {
  if (error instanceof TypeError) {
    const network = lookupMappedMessage(error.message)
    if (network) return network
  }

  for (const candidate of extractErrorCandidates(error)) {
    const resolved = resolveTextCandidate(candidate)
    if (resolved) return resolved
  }

  return UNKNOWN_ERROR_MESSAGE
}
