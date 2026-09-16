import type { SupabaseClient } from "@supabase/supabase-js"
import {
  decryptIntegrationCredentials,
  encryptIntegrationCredentials,
  type AppleSignInRefreshCredentials,
} from "./integrations/credentialEncryption.ts"

function encryptRefreshToken(refreshToken: string): string {
  const payload: AppleSignInRefreshCredentials = {
    kind: "apple_sign_in_refresh",
    refresh_token: refreshToken,
  }
  return encryptIntegrationCredentials(payload)
}

function decryptRefreshToken(ciphertext: string): string {
  const payload = decryptIntegrationCredentials(ciphertext)
  if (payload.kind !== "apple_sign_in_refresh") {
    throw new Error("apple_sign_in_credentials_invalid_kind")
  }
  const token = payload.refresh_token.trim()
  if (!token) {
    throw new Error("apple_sign_in_credentials_empty")
  }
  return token
}

export async function upsertAppleSignInRefreshToken(
  supabase: SupabaseClient,
  params: {
    userId: string
    clientId: string
    refreshToken: string
    appleSub?: string | null
  }
): Promise<void> {
  const ciphertext = encryptRefreshToken(params.refreshToken)
  const { error } = await supabase.from("apple_sign_in_credentials").upsert(
    {
      user_id: params.userId,
      client_id: params.clientId,
      refresh_token_ciphertext: ciphertext,
      apple_sub: params.appleSub ?? null,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "user_id" }
  )
  if (error) {
    throw new Error("apple_sign_in_credentials_upsert_failed")
  }
}

export type AppleSignInCredentialRow = {
  clientId: string
  refreshTokenCiphertext: string
}

export async function loadAppleSignInCredentialRow(
  supabase: SupabaseClient,
  userId: string
): Promise<AppleSignInCredentialRow | null> {
  const { data, error } = await supabase
    .from("apple_sign_in_credentials")
    .select("client_id, refresh_token_ciphertext")
    .eq("user_id", userId)
    .maybeSingle()

  if (error || !data?.refresh_token_ciphertext || !data.client_id) {
    return null
  }

  return {
    clientId: String(data.client_id),
    refreshTokenCiphertext: String(data.refresh_token_ciphertext),
  }
}

export async function loadAppleSignInRefreshToken(
  supabase: SupabaseClient,
  userId: string
): Promise<{ clientId: string; refreshToken: string } | null> {
  const row = await loadAppleSignInCredentialRow(supabase, userId)
  if (!row) return null

  try {
    return {
      clientId: row.clientId,
      refreshToken: decryptRefreshToken(row.refreshTokenCiphertext),
    }
  } catch {
    return null
  }
}

export function decryptAppleSignInRefreshTokenFromCiphertext(
  refreshTokenCiphertext: string
): string | null {
  try {
    return decryptRefreshToken(refreshTokenCiphertext)
  } catch {
    return null
  }
}

export async function deleteAppleSignInCredentials(
  supabase: SupabaseClient,
  userId: string
): Promise<void> {
  await supabase.from("apple_sign_in_credentials").delete().eq("user_id", userId)
}

const ENQUEUE_MAX_ATTEMPTS = 3

export async function enqueueAppleRevokeRetry(
  supabase: SupabaseClient,
  params: {
    clientId: string
    refreshTokenCiphertext: string
    lastError: string
  }
): Promise<boolean> {
  for (let attempt = 1; attempt <= ENQUEUE_MAX_ATTEMPTS; attempt += 1) {
    const { error } = await supabase.from("apple_sign_in_revoke_queue").insert({
      client_id: params.clientId,
      refresh_token_ciphertext: params.refreshTokenCiphertext,
      last_error: params.lastError.slice(0, 500),
      next_attempt_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
    })
    if (!error) {
      return true
    }
    if (attempt < ENQUEUE_MAX_ATTEMPTS) {
      await new Promise((resolve) => setTimeout(resolve, 150 * attempt))
    }
  }
  console.warn("[appleSignInRevocation] enqueue failed after retries")
  return false
}

export function userHasAppleIdentity(
  identities: Array<{ provider?: string | null }> | undefined
): boolean {
  return (identities ?? []).some((identity) => identity.provider === "apple")
}
