import type { Session } from "@supabase/supabase-js"

export type PasswordResetRecoveryStatus = "ready" | "invalid"

/** GoTrue browser key: `sb-<project-ref>-auth-token`. */
export function supabaseBrowserAuthStorageKey(supabaseUrl: string): string | null {
  try {
    const host = new URL(supabaseUrl).hostname
    const ref = host.split(".")[0]?.trim()
    if (!ref) return null
    return `sb-${ref}-auth-token`
  } catch {
    return null
  }
}

function asSession(value: unknown): Session | null {
  if (!value || typeof value !== "object") return null
  const session = value as Session
  const userId = session.user?.id
  const refresh = session.refresh_token
  if (typeof userId !== "string" || userId.length === 0) return null
  if (typeof refresh !== "string" || refresh.length === 0) return null
  if (typeof session.access_token !== "string" || session.access_token.length === 0) {
    return null
  }
  return session
}

/** Read the GoTrue session without asking the client to refresh it. */
export function readStoredSupabaseSession(
  storage: { getItem(key: string): string | null },
  storageKey: string
): Session | null {
  try {
    const raw = storage.getItem(storageKey)
    if (!raw) return null
    return asSession(JSON.parse(raw))
  } catch {
    return null
  }
}

/**
 * INITIAL_SESSION can arrive with a null session when refresh fails inside
 * GoTrue's expiry margin, including a retryable network error. Storage still
 * holds the session in that case. A real sign-out removes it first.
 */
export function shouldHydrateFromStoredSession(input: {
  eventSessionUserId: string | null
  storedSession: Session | null
}): boolean {
  if (input.eventSessionUserId) return false
  return Boolean(input.storedSession?.user?.id)
}

/**
 * A refresh that finishes after the null INITIAL_SESSION must sign the UI
 * back in. A refresh for the user already on screen must not re-bootstrap.
 */
export function shouldApplyDelayedTokenRefresh(input: {
  currentUserId: string | null
  refreshedUserId: string | null
}): boolean {
  if (!input.refreshedUserId) return false
  return input.currentUserId !== input.refreshedUserId
}

/**
 * The recovery hash is often already consumed when this page reads the URL.
 * A stored user means GoTrue accepted the link.
 */
export function passwordResetStatusFromStoredSession(
  storedUserId: string | null
): PasswordResetRecoveryStatus {
  return storedUserId ? "ready" : "invalid"
}
