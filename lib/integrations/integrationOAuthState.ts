import { randomBytes } from "crypto"
import type { SupabaseClient } from "@supabase/supabase-js"

export const INTEGRATION_OAUTH_STATE_TTL_MS = 15 * 60 * 1000

export type IntegrationOAuthProvider = "tradovate"

export type IntegrationOAuthStateRow = {
  user_id: string
  redirect_after: string | null
}

function generateStateToken(): string {
  return randomBytes(32).toString("base64url")
}

/**
 * Called when the user starts a broker OAuth flow (authorize route — next phase).
 * Returns the opaque `state` query param sent to Tradovate.
 */
export async function createIntegrationOAuthState(
  supabase: SupabaseClient,
  params: {
    provider: IntegrationOAuthProvider
    userId: string
    redirectAfter?: string | null
    ttlMs?: number
  }
): Promise<{ state: string; expiresAt: Date }> {
  const state = generateStateToken()
  const expiresAt = new Date(Date.now() + (params.ttlMs ?? INTEGRATION_OAUTH_STATE_TTL_MS))

  const { error } = await supabase.from("integration_oauth_states").insert({
    provider: params.provider,
    state_token: state,
    user_id: params.userId,
    redirect_after: params.redirectAfter ?? null,
    expires_at: expiresAt.toISOString(),
  })

  if (error) {
    throw new Error("integration_oauth_state_create_failed")
  }

  return { state, expiresAt }
}

/**
 * Validates and consumes a one-time state token. Returns the bound user id or null.
 */
export async function consumeIntegrationOAuthState(
  supabase: SupabaseClient,
  params: {
    provider: IntegrationOAuthProvider
    state: string
  }
): Promise<IntegrationOAuthStateRow | null> {
  const trimmed = params.state.trim()
  if (!trimmed) return null

  const now = new Date().toISOString()

  const { data: row, error: selectError } = await supabase
    .from("integration_oauth_states")
    .select("id, user_id, redirect_after, expires_at, consumed_at")
    .eq("provider", params.provider)
    .eq("state_token", trimmed)
    .maybeSingle()

  if (selectError || !row) return null
  if (row.consumed_at) return null
  if (row.expires_at <= now) return null

  const { data: consumed, error: updateError } = await supabase
    .from("integration_oauth_states")
    .update({ consumed_at: now })
    .eq("id", row.id)
    .is("consumed_at", null)
    .gt("expires_at", now)
    .select("user_id, redirect_after")
    .maybeSingle()

  if (updateError || !consumed) return null

  return {
    user_id: consumed.user_id,
    redirect_after: consumed.redirect_after,
  }
}
