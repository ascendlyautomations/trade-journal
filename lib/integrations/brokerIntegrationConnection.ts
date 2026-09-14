import type { SupabaseClient } from "@supabase/supabase-js"
import {
  decryptIntegrationCredentials,
  encryptIntegrationCredentials,
  type IntegrationCredentialPayload,
} from "@/lib/integrations/credentialEncryption"
import type { TradovateApiEnvironment } from "@/lib/integrations/tradovate/tradovateOAuthEnv"

export type BrokerIntegrationProvider = "tradovate"

export type BrokerIntegrationStatus =
  | "connected"
  | "disconnected"
  | "error"
  | "reconnect_required"

export type SafeBrokerIntegrationView = {
  provider: BrokerIntegrationProvider
  connected: boolean
  status: BrokerIntegrationStatus
  connected_at: string | null
  last_sync_at: string | null
  provider_user_id: string | null
  api_environment: TradovateApiEnvironment | null
}

type ConnectionRow = {
  id: string
  user_id: string
  provider: string
  status: string
  provider_user_id: string | null
  credentials_ciphertext: string | null
  access_token_expires_at: string | null
  refresh_token_expires_at: string | null
  api_environment: string | null
  connected_at: string | null
  disconnected_at: string | null
  last_sync_at: string | null
}

function toSafeView(row: ConnectionRow | null, provider: BrokerIntegrationProvider): SafeBrokerIntegrationView {
  const connected = row?.status === "connected"
  return {
    provider,
    connected,
    status: (row?.status as BrokerIntegrationStatus) ?? "disconnected",
    connected_at: row?.connected_at ?? null,
    last_sync_at: row?.last_sync_at ?? null,
    provider_user_id: connected ? row?.provider_user_id ?? null : null,
    api_environment:
      connected && (row?.api_environment === "demo" || row?.api_environment === "live")
        ? row.api_environment
        : null,
  }
}

export async function upsertTradovateConnection(
  supabase: SupabaseClient,
  params: {
    userId: string
    providerUserId: string | null
    credentials: IntegrationCredentialPayload
    accessTokenExpiresAt: Date | null
    refreshTokenExpiresAt: Date | null
    apiEnvironment: TradovateApiEnvironment
  }
): Promise<void> {
  const now = new Date().toISOString()
  const ciphertext = encryptIntegrationCredentials(params.credentials)

  const { error } = await supabase.from("broker_integration_connections").upsert(
    {
      user_id: params.userId,
      provider: "tradovate",
      status: "connected",
      provider_user_id: params.providerUserId,
      credentials_ciphertext: ciphertext,
      access_token_expires_at: params.accessTokenExpiresAt?.toISOString() ?? null,
      refresh_token_expires_at: params.refreshTokenExpiresAt?.toISOString() ?? null,
      api_environment: params.apiEnvironment,
      connected_at: now,
      disconnected_at: null,
      updated_at: now,
    },
    { onConflict: "user_id,provider" }
  )

  if (error) {
    throw new Error("broker_integration_connection_upsert_failed")
  }
}

export async function disconnectBrokerIntegration(
  supabase: SupabaseClient,
  params: {
    userId: string
    provider: BrokerIntegrationProvider
  }
): Promise<boolean> {
  const now = new Date().toISOString()
  const { data: active, error: loadError } = await supabase
    .from("broker_integration_connections")
    .select("id, status")
    .eq("user_id", params.userId)
    .eq("provider", params.provider)
    .in("status", ["connected", "reconnect_required", "error"])
    .maybeSingle()

  if (loadError) {
    throw new Error("broker_integration_disconnect_failed")
  }
  if (!active) return false

  const { disableBrokerAccountsForConnection } = await import(
    "@/lib/integrations/brokerIntegrationAccounts"
  )
  await disableBrokerAccountsForConnection(supabase, {
    userId: params.userId,
    connectionId: active.id,
  })

  const { data, error } = await supabase
    .from("broker_integration_connections")
    .update({
      status: "disconnected",
      credentials_ciphertext: null,
      access_token_expires_at: null,
      refresh_token_expires_at: null,
      disconnected_at: now,
      updated_at: now,
    })
    .eq("id", active.id)
    .select("id")
    .maybeSingle()

  if (error) {
    throw new Error("broker_integration_disconnect_failed")
  }
  return Boolean(data)
}

export async function loadSafeBrokerIntegration(
  supabase: SupabaseClient,
  params: {
    userId: string
    provider: BrokerIntegrationProvider
  }
): Promise<SafeBrokerIntegrationView> {
  const { data, error } = await supabase
    .from("broker_integration_connections")
    .select(
      "id, user_id, provider, status, provider_user_id, credentials_ciphertext, access_token_expires_at, refresh_token_expires_at, api_environment, connected_at, disconnected_at, last_sync_at"
    )
    .eq("user_id", params.userId)
    .eq("provider", params.provider)
    .maybeSingle()

  if (error) {
    throw new Error("broker_integration_status_load_failed")
  }

  return toSafeView((data as ConnectionRow | null) ?? null, params.provider)
}

/** Service-role only: decrypt stored OAuth credentials for server-side Tradovate API calls. */
export async function loadBrokerIntegrationCredentials(
  supabase: SupabaseClient,
  params: {
    userId: string
    provider: BrokerIntegrationProvider
  }
): Promise<IntegrationCredentialPayload | null> {
  const { data, error } = await supabase
    .from("broker_integration_connections")
    .select("status, credentials_ciphertext")
    .eq("user_id", params.userId)
    .eq("provider", params.provider)
    .maybeSingle()

  if (error || !data || data.status !== "connected") return null
  const ciphertext = data.credentials_ciphertext
  if (!ciphertext || typeof ciphertext !== "string") return null
  return decryptIntegrationCredentials(ciphertext)
}
