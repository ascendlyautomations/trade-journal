import type { SupabaseClient } from "@supabase/supabase-js"
import {
  appleSignInOAuthConfigured,
  exchangeAppleAuthorizationCode,
  resolveAppleSignInOAuthConfig,
  revokeAppleRefreshToken,
} from "./appleSignInOAuth.ts"
import {
  decryptAppleSignInRefreshTokenFromCiphertext,
  deleteAppleSignInCredentials,
  enqueueAppleRevokeRetry,
  loadAppleSignInCredentialRow,
  upsertAppleSignInRefreshToken,
  userHasAppleIdentity,
} from "./appleSignInCredentialStore.ts"

export type AppleRevocationOutcome =
  | "not_applicable"
  | "revoked"
  | "legacy_no_token"
  | "queued_for_retry"
  | "queue_persistence_failed"
  | "misconfigured"

export async function storeAppleAuthorizationCodeForUser(
  supabase: SupabaseClient,
  userId: string,
  authorizationCode: string
): Promise<{ stored: boolean }> {
  const config = resolveAppleSignInOAuthConfig()
  if (!config) {
    return { stored: false }
  }

  const exchanged = await exchangeAppleAuthorizationCode(authorizationCode, config)
  if (!exchanged.ok) {
    return { stored: false }
  }

  await upsertAppleSignInRefreshToken(supabase, {
    userId,
    clientId: config.clientId,
    refreshToken: exchanged.refreshToken,
  })

  return { stored: true }
}

export async function revokeAppleSignInBeforeUserDelete(
  supabase: SupabaseClient,
  targetUserId: string
): Promise<AppleRevocationOutcome> {
  const { data: authData } = await supabase.auth.admin.getUserById(targetUserId)
  const authUser = authData.user
  if (!authUser) {
    return "not_applicable"
  }

  if (!userHasAppleIdentity(authUser.identities)) {
    return "not_applicable"
  }

  const config = resolveAppleSignInOAuthConfig()
  if (!config || !appleSignInOAuthConfigured()) {
    console.warn(
      `[deleteUserAdmin] Apple Sign in revocation skipped (misconfigured) userId=${targetUserId}`
    )
    await deleteAppleSignInCredentials(supabase, targetUserId)
    return "misconfigured"
  }

  const stored = await loadAppleSignInCredentialRow(supabase, targetUserId)
  if (!stored) {
    await deleteAppleSignInCredentials(supabase, targetUserId)
    return "legacy_no_token"
  }

  const revokeConfig = {
    ...config,
    clientId: stored.clientId || config.clientId,
  }

  const refreshToken = decryptAppleSignInRefreshTokenFromCiphertext(
    stored.refreshTokenCiphertext
  )
  if (!refreshToken) {
    await deleteAppleSignInCredentials(supabase, targetUserId)
    return "legacy_no_token"
  }

  const revoked = await revokeAppleRefreshToken(refreshToken, revokeConfig)
  if (revoked.ok) {
    await deleteAppleSignInCredentials(supabase, targetUserId)
    return "revoked"
  }

  if (revoked.reason === "terminal" || revoked.reason === "misconfigured") {
    await deleteAppleSignInCredentials(supabase, targetUserId)
    console.warn(
      `[deleteUserAdmin] Apple Sign in revoke terminal userId=${targetUserId} reason=${revoked.reason}`
    )
    return "revoked"
  }

  const enqueued = await enqueueAppleRevokeRetry(supabase, {
    clientId: revokeConfig.clientId,
    refreshTokenCiphertext: stored.refreshTokenCiphertext,
    lastError: revoked.reason,
  })

  if (enqueued) {
    await deleteAppleSignInCredentials(supabase, targetUserId)
    console.warn(
      `[deleteUserAdmin] Apple Sign in revoke deferred userId=${targetUserId} reason=${revoked.reason}`
    )
    return "queued_for_retry"
  }

  console.warn(
    `[deleteUserAdmin] Apple Sign in revoke queue persistence failed userId=${targetUserId}`
  )
  await deleteAppleSignInCredentials(supabase, targetUserId)
  return "queue_persistence_failed"
}
