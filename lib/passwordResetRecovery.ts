import type { AuthChangeEvent, Session, SupabaseClient } from "@supabase/supabase-js"

export type PasswordResetRecoveryStatus = "ready" | "invalid"

const RECOVERY_VERIFY_TIMEOUT_MS = 8000
const HASH_PROCESS_DELAY_MS = 400

function parseHashParams(): URLSearchParams {
  if (typeof window === "undefined") return new URLSearchParams()
  const raw = window.location.hash.startsWith("#")
    ? window.location.hash.slice(1)
    : window.location.hash
  return new URLSearchParams(raw)
}

function hasRecoveryUrlIndicators(): boolean {
  const query = new URLSearchParams(window.location.search)
  const hash = parseHashParams()
  if (query.get("code")) return true
  if (hash.get("type") === "recovery") return true
  if (hash.get("access_token") && hash.get("type") === "recovery") return true
  return false
}

function getAuthErrorFromUrl(): string | null {
  const hash = parseHashParams()
  const query = new URLSearchParams(window.location.search)
  return (
    hash.get("error_description") ||
    hash.get("error") ||
    query.get("error_description") ||
    query.get("error")
  )
}

function cleanRecoveryUrl() {
  window.history.replaceState({}, document.title, window.location.pathname)
}

function isExpiredAuthMessage(message: string): boolean {
  const lower = message.toLowerCase()
  return lower.includes("expired") || lower.includes("otp_expired")
}

/**
 * Establishes a Supabase recovery session from email link (hash or PKCE code).
 * Resolves "ready" only when recovery credentials were present and accepted.
 */
export function establishPasswordResetRecovery(
  supabase: SupabaseClient
): Promise<PasswordResetRecoveryStatus> {
  return new Promise((resolve) => {
    let settled = false
    let timeoutId: ReturnType<typeof setTimeout> | undefined

    const finish = (status: PasswordResetRecoveryStatus) => {
      if (settled) return
      settled = true
      if (timeoutId) clearTimeout(timeoutId)
      subscription.unsubscribe()
      resolve(status)
    }

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event: AuthChangeEvent, session: Session | null) => {
      if (event === "PASSWORD_RECOVERY" && session) {
        cleanRecoveryUrl()
        finish("ready")
      }
    })

    async function run() {
      const urlError = getAuthErrorFromUrl()
      if (urlError) {
        finish("invalid")
        return
      }

      if (!hasRecoveryUrlIndicators()) {
        await delay(HASH_PROCESS_DELAY_MS)
        finish("invalid")
        return
      }

      const query = new URLSearchParams(window.location.search)
      const code = query.get("code")

      if (code) {
        const { error } = await supabase.auth.exchangeCodeForSession(code)
        cleanRecoveryUrl()

        if (error) {
          finish("invalid")
          return
        }

        const {
          data: { session },
        } = await supabase.auth.getSession()

        finish(session ? "ready" : "invalid")
        return
      }

      const hash = parseHashParams()
      const isRecoveryHash = hash.get("type") === "recovery"

      if (isRecoveryHash || hash.get("access_token")) {
        await supabase.auth.getSession()
        await delay(HASH_PROCESS_DELAY_MS)

        const {
          data: { session },
        } = await supabase.auth.getSession()

        if (session && isRecoveryHash) {
          cleanRecoveryUrl()
          finish("ready")
          return
        }
      }

      finish("invalid")
    }

    timeoutId = setTimeout(() => finish("invalid"), RECOVERY_VERIFY_TIMEOUT_MS)
    void run()
  })
}

function delay(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

export function mapPasswordUpdateError(error: unknown): string {
  if (!error || typeof error !== "object") {
    return "Something went wrong. Please try again."
  }

  const message =
    "message" in error && typeof (error as { message: unknown }).message === "string"
      ? (error as { message: string }).message
      : ""

  const lower = message.toLowerCase()

  if (
    lower.includes("session") ||
    lower.includes("jwt") ||
    lower.includes("not authenticated") ||
    isExpiredAuthMessage(lower)
  ) {
    return "Your reset link has expired. Please request a new one."
  }

  if (lower.includes("network") || lower.includes("fetch") || lower.includes("failed to fetch")) {
    return "Network error. Check your connection and try again."
  }

  if (lower.includes("same password")) {
    return "Choose a different password than your current one."
  }

  if (
    lower.includes("weak") ||
    lower.includes("too short") ||
    lower.includes("at least")
  ) {
    return `Password must be at least ${PASSWORD_MIN_LENGTH} characters.`
  }

  return "Could not update your password. Please try again or request a new reset link."
}

/** In-app password create/change (signed-in user) — no reset-email wording. */
export function mapInAppPasswordUpdateError(error: unknown): string {
  const message = mapPasswordUpdateError(error)
  if (message.includes("reset link")) {
    return "Could not save your password. Please try again."
  }
  return message
}

export const PASSWORD_MIN_LENGTH = 6

export function validatePasswordPair(
  password: string,
  confirmPassword: string
): { password?: string; confirmPassword?: string } {
  const errors: { password?: string; confirmPassword?: string } = {}

  if (password.length > 0 && password.length < PASSWORD_MIN_LENGTH) {
    errors.password = `Password must be at least ${PASSWORD_MIN_LENGTH} characters.`
  }

  if (confirmPassword.length > 0 && password !== confirmPassword) {
    errors.confirmPassword = "Passwords do not match."
  }

  return errors
}

export function isPasswordPairValid(password: string, confirmPassword: string): boolean {
  return (
    password.length >= PASSWORD_MIN_LENGTH &&
    confirmPassword.length >= PASSWORD_MIN_LENGTH &&
    password === confirmPassword
  )
}
