/**
 * Central registry: map internal error codes → polished user-facing copy.
 * Add new mappings here only — do not scatter conditionals across the app.
 */
export const USER_FACING_ERROR_MESSAGES = {
  FREE_PLAN_DAILY_POST_LIMIT:
    "Free accounts can create 1 post every 24 hours. Upgrade to Pro for unlimited posting.",
  FREE_PLAN_DAILY_TRADE_LIMIT:
    "You've reached the Free plan limit of 3 trades every 24 hours. Upgrade to Pro for unlimited trades.",
  FREE_PLAN_REELS_LIMIT:
    "Free accounts can upload 1 clip every 24 hours. Upgrade to Pro for unlimited clips.",
  FREE_PLAN_ACCOUNT_LIMIT:
    "Free plan allows up to 3 accounts. Upgrade to Pro for unlimited accounts.",
  RATE_LIMIT_EXCEEDED:
    "You're doing that too often. Please wait a moment and try again.",
  UNAUTHORIZED:
    "You don't have permission to perform this action.",
  SESSION_EXPIRED: "Your session has expired. Please sign in again.",
  BILLING_UNAVAILABLE:
    "Billing is temporarily unavailable. Please try again later.",
  USERNAME_TAKEN: "This username is already taken.",
  DUPLICATE_ENTRY: "This already exists. Please try a different value.",
  ITEM_NOT_FOUND: "This item could not be found.",
  FILE_TOO_LARGE: "This file is too large.",
  NETWORK_ERROR:
    "We couldn't reach our servers. Please try again in a moment.",
  CONNECTION_ERROR:
    "Couldn't connect to TradeTraxs. Check your internet connection and try again.",
  TRADE_SAVE_FAILED: "Your trade couldn't be saved. Please try again.",
  TRADE_IMAGE_UPLOAD_FAILED: "We couldn't upload your trade image.",
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

function isNumericPgCode(text: string): boolean {
  return /^\d{5}$/.test(text.trim())
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

function looksLikeTechnicalDbMessage(text: string): boolean {
  const lower = text.toLowerCase()
  return (
    lower.includes("duplicate key") ||
    lower.includes("violates unique constraint") ||
    lower.includes("violates foreign key") ||
    lower.includes("foreign key violation") ||
    lower.includes("row-level security") ||
    lower.includes("permission denied for") ||
    lower.includes("schema cache") ||
    lower.includes("postgrest") ||
    lower.includes("jwt") ||
    lower.includes("constraint") ||
    isBarePostgresCode(text) ||
    isPostgrestCode(text) ||
    isNumericPgCode(text)
  )
}

function looksLikeStripeInternal(text: string): boolean {
  const lower = text.toLowerCase()
  return (
    lower.includes("stripe") ||
    lower.includes("no such customer") ||
    lower.includes("no such subscription") ||
    lower.includes("invalid api key")
  )
}

function looksLikeConfigError(text: string): boolean {
  const upper = text.toUpperCase()
  return (
    upper.includes("MISSING STRIPE") ||
    upper.includes("STRIPE_SECRET") ||
    upper.includes("RESEND_API_KEY") ||
    upper.includes("OPENAI_API_KEY") ||
    upper.includes("SUPABASE_SERVICE_ROLE")
  )
}

/** Sentences from Postgres `raise exception '...'` — show when user-friendly. */
function isHumanReadableSentence(text: string): boolean {
  const t = text.trim()
  if (!t || t.length < 4) return false
  if (isInternalConstant(t)) return false
  if (looksLikeTechnicalDbMessage(t)) return false
  if (looksLikeStripeInternal(t)) return false
  if (looksLikeConfigError(t)) return false
  if (looksLikeStackTrace(t)) return false
  return /[a-z]/.test(t)
}

function mapFreePlanMessage(text: string): string | null {
  const lower = text.toLowerCase()
  if (!lower.includes("free") && !lower.includes("upgrade to pro")) return null

  if (lower.includes("post") && (lower.includes("24 hour") || lower.includes("daily"))) {
    return USER_FACING_ERROR_MESSAGES.FREE_PLAN_DAILY_POST_LIMIT
  }
  if (lower.includes("trade") && (lower.includes("24 hour") || lower.includes("daily") || lower.includes("3"))) {
    return USER_FACING_ERROR_MESSAGES.FREE_PLAN_DAILY_TRADE_LIMIT
  }
  if (lower.includes("reel")) {
    return USER_FACING_ERROR_MESSAGES.FREE_PLAN_REELS_LIMIT
  }
  if (lower.includes("account")) {
    return USER_FACING_ERROR_MESSAGES.FREE_PLAN_ACCOUNT_LIMIT
  }
  return null
}

function lookupMappedMessage(text: string): string | null {
  const trimmed = text.trim()
  const upper = trimmed.toUpperCase()
  const lower = trimmed.toLowerCase()

  if (upper in USER_FACING_ERROR_MESSAGES) {
    return USER_FACING_ERROR_MESSAGES[upper as UserFacingErrorCode]
  }

  const head = trimmed.split(":")[0]?.trim().toUpperCase() ?? ""
  if (head && head in USER_FACING_ERROR_MESSAGES) {
    return USER_FACING_ERROR_MESSAGES[head as UserFacingErrorCode]
  }

  const freePlan = mapFreePlanMessage(trimmed)
  if (freePlan) return freePlan

  if (lower.includes("rate_limit_exceeded")) {
    return USER_FACING_ERROR_MESSAGES.RATE_LIMIT_EXCEEDED
  }

  if (
    lower.includes("jwt expired") ||
    lower.includes("token expired") ||
    lower.includes("invalid jwt") ||
    lower.includes("session expired")
  ) {
    return USER_FACING_ERROR_MESSAGES.SESSION_EXPIRED
  }

  if (
    lower.includes("username") &&
    (lower.includes("taken") ||
      lower.includes("already exists") ||
      lower.includes("duplicate"))
  ) {
    return USER_FACING_ERROR_MESSAGES.USERNAME_TAKEN
  }

  if (lower.includes("account with this name already exists")) {
    return "An account with this name already exists."
  }

  if (
    lower.includes("duplicate key") ||
    lower.includes("unique constraint") ||
    (lower.includes("already exists") && !lower.includes("account with this name"))
  ) {
    if (lower.includes("username") || lower.includes("profiles_username")) {
      return USER_FACING_ERROR_MESSAGES.USERNAME_TAKEN
    }
    return USER_FACING_ERROR_MESSAGES.DUPLICATE_ENTRY
  }

  if (
    lower.includes("foreign key") ||
    lower.includes("23503") ||
    lower.includes("not found") ||
    lower.includes("no rows")
  ) {
    return USER_FACING_ERROR_MESSAGES.ITEM_NOT_FOUND
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
    lower === "unauthorized" ||
    lower.includes("42501")
  ) {
    return USER_FACING_ERROR_MESSAGES.UNAUTHORIZED
  }

  if (looksLikeConfigError(trimmed)) {
    return USER_FACING_ERROR_MESSAGES.BILLING_UNAVAILABLE
  }

  if (looksLikeStripeInternal(trimmed)) {
    return USER_FACING_ERROR_MESSAGES.BILLING_UNAVAILABLE
  }

  if (
    lower.includes("failed to fetch") ||
    lower.includes("networkerror") ||
    lower.includes("network request failed") ||
    lower.includes("load failed") ||
    lower === "network error"
  ) {
    return USER_FACING_ERROR_MESSAGES.NETWORK_ERROR
  }

  if (lower.includes("network") && lower.includes("error")) {
    return USER_FACING_ERROR_MESSAGES.CONNECTION_ERROR
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

  if (e.code) {
    candidates.push(e.code)
    if (isNumericPgCode(e.code)) {
      if (e.code === "23505") candidates.push("duplicate key")
      if (e.code === "23503") candidates.push("foreign key")
      if (e.code === "42501") candidates.push("permission denied")
    }
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
export function toUserFacingErrorMessage(
  error: unknown,
  fallback: string = UNKNOWN_ERROR_MESSAGE
): string {
  if (error instanceof TypeError) {
    const network = lookupMappedMessage(error.message)
    if (network) return network
  }

  for (const candidate of extractErrorCandidates(error)) {
    const resolved = resolveTextCandidate(candidate)
    if (resolved) return resolved
  }

  return fallback
}

/** JSON error body for API routes — never exposes internal details. */
export function jsonUserFacingError(
  error: unknown,
  status = 500,
  context?: string
): Response {
  if (context) logErrorForDevelopers(context, error)
  else logErrorForDevelopers("api", error)
  return Response.json(
    { error: toUserFacingErrorMessage(error) },
    { status }
  )
}
