import type { SupabaseClient } from "@supabase/supabase-js"
import {
  appleSignInOAuthConfigured,
  resolveAppleSignInOAuthConfig,
  revokeAppleRefreshToken,
} from "./appleSignInOAuth.ts"
import { decryptAppleSignInRefreshTokenFromCiphertext } from "./appleSignInCredentialStore.ts"

/** First retry after enqueue (account deletion path). */
export const APPLE_REVOKE_QUEUE_INITIAL_DELAY_MS = 15 * 60 * 1000

/** Bounded exponential backoff base for worker retries. */
export const APPLE_REVOKE_QUEUE_BACKOFF_BASE_MS = 15 * 60 * 1000

/** Maximum backoff between worker attempts (24 hours). */
export const APPLE_REVOKE_QUEUE_BACKOFF_CAP_MS = 24 * 60 * 60 * 1000

/** Drop queue material after this many failed attempts (includes claim cycles). */
export const APPLE_REVOKE_QUEUE_MAX_ATTEMPTS = 12

export const APPLE_REVOKE_QUEUE_DEFAULT_BATCH_SIZE = 10

export type AppleRevokeQueueRow = {
  id: string
  client_id: string
  refresh_token_ciphertext: string
  attempts: number
  last_error: string | null
  created_at: string
  next_attempt_at: string
  lease_expires_at: string | null
}

export function computeAppleRevokeQueueNextAttemptAt(
  attemptsAfterFailure: number,
  nowMs = Date.now()
): string {
  const exponent = Math.max(0, attemptsAfterFailure - 1)
  const delayMs = Math.min(
    APPLE_REVOKE_QUEUE_BACKOFF_BASE_MS * 2 ** exponent,
    APPLE_REVOKE_QUEUE_BACKOFF_CAP_MS
  )
  return new Date(nowMs + delayMs).toISOString()
}

export async function claimAppleRevokeQueueBatch(
  supabase: SupabaseClient,
  limit = APPLE_REVOKE_QUEUE_DEFAULT_BATCH_SIZE
): Promise<AppleRevokeQueueRow[]> {
  const { data, error } = await supabase.rpc("claim_apple_sign_in_revoke_queue", {
    p_limit: limit,
  })
  if (error || !data) {
    return []
  }
  return data as AppleRevokeQueueRow[]
}

export type AppleRevokeQueueWorkerResult = {
  claimed: number
  revoked: number
  rescheduled: number
  removedTerminal: number
  removedExpired: number
  skippedMisconfigured: number
}

export async function processAppleSignInRevokeQueue(
  supabase: SupabaseClient,
  options: {
    batchSize?: number
    fetchImpl?: typeof fetch
  } = {}
): Promise<AppleRevokeQueueWorkerResult> {
  const result: AppleRevokeQueueWorkerResult = {
    claimed: 0,
    revoked: 0,
    rescheduled: 0,
    removedTerminal: 0,
    removedExpired: 0,
    skippedMisconfigured: 0,
  }

  if (!appleSignInOAuthConfigured()) {
    result.skippedMisconfigured = 1
    return result
  }

  const config = resolveAppleSignInOAuthConfig()
  if (!config) {
    result.skippedMisconfigured = 1
    return result
  }

  const rows = await claimAppleRevokeQueueBatch(
    supabase,
    options.batchSize ?? APPLE_REVOKE_QUEUE_DEFAULT_BATCH_SIZE
  )
  result.claimed = rows.length

  for (const row of rows) {
    const nextAttempts = row.attempts + 1

    if (nextAttempts > APPLE_REVOKE_QUEUE_MAX_ATTEMPTS) {
      await supabase.from("apple_sign_in_revoke_queue").delete().eq("id", row.id)
      result.removedExpired += 1
      continue
    }

    const refreshToken = decryptAppleSignInRefreshTokenFromCiphertext(
      row.refresh_token_ciphertext
    )
    if (!refreshToken) {
      await supabase.from("apple_sign_in_revoke_queue").delete().eq("id", row.id)
      result.removedTerminal += 1
      continue
    }

    const revokeConfig = {
      ...config,
      clientId: row.client_id || config.clientId,
    }

    const revoked = await revokeAppleRefreshToken(
      refreshToken,
      revokeConfig,
      options.fetchImpl
    )

    if (revoked.ok) {
      await supabase.from("apple_sign_in_revoke_queue").delete().eq("id", row.id)
      result.revoked += 1
      continue
    }

    if (revoked.reason === "terminal") {
      await supabase.from("apple_sign_in_revoke_queue").delete().eq("id", row.id)
      result.removedTerminal += 1
      continue
    }

    if (revoked.reason === "misconfigured") {
      await supabase
        .from("apple_sign_in_revoke_queue")
        .update({
          attempts: nextAttempts,
          last_error: revoked.reason,
          next_attempt_at: computeAppleRevokeQueueNextAttemptAt(nextAttempts),
          lease_expires_at: null,
        })
        .eq("id", row.id)
      result.rescheduled += 1
      continue
    }

    await supabase
      .from("apple_sign_in_revoke_queue")
      .update({
        attempts: nextAttempts,
        last_error: revoked.reason,
        next_attempt_at: computeAppleRevokeQueueNextAttemptAt(nextAttempts),
        lease_expires_at: null,
      })
      .eq("id", row.id)
    result.rescheduled += 1
  }

  return result
}
