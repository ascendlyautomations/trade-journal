import { randomBytes } from "crypto"
import type { SupabaseClient } from "@supabase/supabase-js"

export const INTEGRATION_OAUTH_STATE_TTL_MS = 15 * 60 * 1000

export type IntegrationOAuthProvider = "tradovate"

export type IntegrationOAuthIntent = "connect_new" | "reconnect"

export type IntegrationOAuthStateRow = {
  user_id: string
  redirect_after: string | null
  oauth_intent: IntegrationOAuthIntent
  target_connection_id: string | null
}

function generateStateToken(): string {
  return randomBytes(32).toString("base64url")
}

export async function createIntegrationOAuthState(
  supabase: SupabaseClient,
  params: {
    provider: IntegrationOAuthProvider
    userId: string
    redirectAfter?: string | null
    ttlMs?: number
    oauthIntent?: IntegrationOAuthIntent
    targetConnectionId?: string | null
  }
): Promise<{ state: string; expiresAt: Date }> {
  const state = generateStateToken()
  const expiresAt = new Date(Date.now() + (params.ttlMs ?? INTEGRATION_OAUTH_STATE_TTL_MS))
  const intent = params.oauthIntent ?? "connect_new"

  const { error } = await supabase.from("integration_oauth_states").insert({
    provider: params.provider,
    state_token: state,
    user_id: params.userId,
    redirect_after: params.redirectAfter ?? null,
    expires_at: expiresAt.toISOString(),
    oauth_intent: intent,
    target_connection_id:
      intent === "reconnect" ? (params.targetConnectionId ?? null) : null,
  })

  if (error) {
    throw new Error("integration_oauth_state_create_failed")
  }

  return { state, expiresAt }
}

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
    .select(
      "id, user_id, redirect_after, expires_at, consumed_at, oauth_intent, target_connection_id"
    )
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
    .select("user_id, redirect_after, oauth_intent, target_connection_id")
    .maybeSingle()

  if (updateError || !consumed) return null

  return {
    user_id: consumed.user_id,
    redirect_after: consumed.redirect_after,
    oauth_intent:
      consumed.oauth_intent === "reconnect" ? "reconnect" : "connect_new",
    target_connection_id: consumed.target_connection_id ?? null,
  }
}
