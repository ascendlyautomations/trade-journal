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

export type SafeBrokerConnectionView = {
  id: string
  provider: BrokerIntegrationProvider
  connected: boolean
  status: BrokerIntegrationStatus
  label: string
  connected_at: string | null
  last_sync_at: string | null
  provider_user_id: string | null
  provider_display_name: string | null
  connection_label: string | null
  api_environment: TradovateApiEnvironment | null
}

type ConnectionRow = {
  id: string
  user_id: string
  provider: string
  status: string
  provider_user_id: string | null
  provider_display_name: string | null
  connection_label: string | null
  credentials_ciphertext: string | null
  access_token_expires_at: string | null
  refresh_token_expires_at: string | null
  api_environment: string | null
  connected_at: string | null
  disconnected_at: string | null
  last_sync_at: string | null
}

const ACTIVE_STATUSES = ["connected", "reconnect_required", "error"] as const

function connectionLabel(row: ConnectionRow, index: number): string {
  if (row.connection_label?.trim()) return row.connection_label.trim()
  if (row.provider_display_name?.trim()) return row.provider_display_name.trim()
  return `Tradovate Connection ${index + 1}`
}

function toSafeConnectionView(
  row: ConnectionRow,
  index: number
): SafeBrokerConnectionView {
  const connected = row.status === "connected"
  return {
    id: row.id,
    provider: row.provider as BrokerIntegrationProvider,
    connected,
    status: (row.status as BrokerIntegrationStatus) ?? "disconnected",
    label: connectionLabel(row, index),
    connected_at: row.connected_at,
    last_sync_at: row.last_sync_at,
    provider_user_id: connected ? row.provider_user_id : null,
    provider_display_name: row.provider_display_name,
    connection_label: row.connection_label,
    api_environment:
      connected && (row.api_environment === "demo" || row.api_environment === "live")
        ? row.api_environment
        : null,
  }
}

export class BrokerOAuthIdentityMismatchError extends Error {
  constructor() {
    super("broker_oauth_identity_mismatch")
    this.name = "BrokerOAuthIdentityMismatchError"
  }
}

export async function listSafeBrokerConnections(
  supabase: SupabaseClient,
  params: {
    userId: string
    provider: BrokerIntegrationProvider
    includeInactive?: boolean
  }
): Promise<SafeBrokerConnectionView[]> {
  let query = supabase
    .from("broker_integration_connections")
    .select(
      "id, user_id, provider, status, provider_user_id, provider_display_name, connection_label, credentials_ciphertext, access_token_expires_at, refresh_token_expires_at, api_environment, connected_at, disconnected_at, last_sync_at"
    )
    .eq("user_id", params.userId)
    .eq("provider", params.provider)
    .order("connected_at", { ascending: true, nullsFirst: false })

  if (!params.includeInactive) {
    query = query.in("status", [...ACTIVE_STATUSES])
  }

  const { data, error } = await query
  if (error) throw new Error("broker_integration_connections_list_failed")

  const rows = (data ?? []) as ConnectionRow[]
  return rows.map((row, index) => toSafeConnectionView(row, index))
}

/** @deprecated Use listSafeBrokerConnections — kept for legacy status route. */
export async function loadSafeBrokerIntegration(
  supabase: SupabaseClient,
  params: {
    userId: string
    provider: BrokerIntegrationProvider
  }
): Promise<SafeBrokerConnectionView & { provider: BrokerIntegrationProvider }> {
  const list = await listSafeBrokerConnections(supabase, params)
  const first = list[0]
  if (!first) {
    return {
      id: "",
      provider: params.provider,
      connected: false,
      status: "disconnected",
      label: "Tradovate",
      connected_at: null,
      last_sync_at: null,
      provider_user_id: null,
      provider_display_name: null,
      connection_label: null,
      api_environment: null,
    }
  }
  return first
}

async function findActiveConnectionByProviderUserId(
  supabase: SupabaseClient,
  params: {
    userId: string
    provider: BrokerIntegrationProvider
    providerUserId: string
  }
): Promise<ConnectionRow | null> {
  const { data } = await supabase
    .from("broker_integration_connections")
    .select(
      "id, user_id, provider, status, provider_user_id, provider_display_name, connection_label, credentials_ciphertext, access_token_expires_at, refresh_token_expires_at, api_environment, connected_at, disconnected_at, last_sync_at"
    )
    .eq("user_id", params.userId)
    .eq("provider", params.provider)
    .eq("provider_user_id", params.providerUserId)
    .in("status", [...ACTIVE_STATUSES])
    .maybeSingle()

  return (data as ConnectionRow | null) ?? null
}

export async function persistTradovateConnectionAfterOAuth(
  supabase: SupabaseClient,
  params: {
    userId: string
    providerUserId: string | null
    providerDisplayName: string | null
    credentials: IntegrationCredentialPayload
    accessTokenExpiresAt: Date | null
    refreshTokenExpiresAt: Date | null
    apiEnvironment: TradovateApiEnvironment
    oauthIntent: "connect_new" | "reconnect"
    targetConnectionId?: string | null
  }
): Promise<{ connectionId: string }> {
  const now = new Date().toISOString()
  const ciphertext = encryptIntegrationCredentials(params.credentials)

  const baseUpdate = {
    status: "connected" as const,
    provider_user_id: params.providerUserId,
    provider_display_name: params.providerDisplayName,
    credentials_ciphertext: ciphertext,
    access_token_expires_at: params.accessTokenExpiresAt?.toISOString() ?? null,
    refresh_token_expires_at: params.refreshTokenExpiresAt?.toISOString() ?? null,
    api_environment: params.apiEnvironment,
    connected_at: now,
    disconnected_at: null,
    updated_at: now,
  }

  if (params.oauthIntent === "reconnect" && params.targetConnectionId) {
    const { data: target, error: targetError } = await supabase
      .from("broker_integration_connections")
      .select("id, user_id, provider, provider_user_id, status")
      .eq("id", params.targetConnectionId)
      .eq("user_id", params.userId)
      .eq("provider", "tradovate")
      .maybeSingle()

    if (targetError || !target) {
      throw new Error("broker_integration_reconnect_target_not_found")
    }

    if (
      params.providerUserId &&
      target.provider_user_id &&
      target.provider_user_id !== params.providerUserId
    ) {
      throw new BrokerOAuthIdentityMismatchError()
    }

    const { error } = await supabase
      .from("broker_integration_connections")
      .update({
        ...baseUpdate,
        provider_user_id: params.providerUserId ?? target.provider_user_id,
      })
      .eq("id", target.id)

    if (error) throw new Error("broker_integration_connection_update_failed")
    return { connectionId: target.id }
  }

  if (params.providerUserId) {
    const existing = await findActiveConnectionByProviderUserId(supabase, {
      userId: params.userId,
      provider: "tradovate",
      providerUserId: params.providerUserId,
    })
    if (existing) {
      const { error } = await supabase
        .from("broker_integration_connections")
        .update(baseUpdate)
        .eq("id", existing.id)
      if (error) throw new Error("broker_integration_connection_update_failed")
      return { connectionId: existing.id }
    }
  }

  const { data: inserted, error: insertError } = await supabase
    .from("broker_integration_connections")
    .insert({
      user_id: params.userId,
      provider: "tradovate",
      ...baseUpdate,
    })
    .select("id")
    .single()

  if (insertError || !inserted) {
    throw new Error("broker_integration_connection_insert_failed")
  }

  return { connectionId: inserted.id as string }
}

export async function updateBrokerConnectionCredentials(
  supabase: SupabaseClient,
  params: {
    connectionId: string
    userId: string
    credentials: IntegrationCredentialPayload
    accessTokenExpiresAt: Date | null
    refreshTokenExpiresAt: Date | null
  }
): Promise<void> {
  const ciphertext = encryptIntegrationCredentials(params.credentials)
  const { error } = await supabase
    .from("broker_integration_connections")
    .update({
      credentials_ciphertext: ciphertext,
      access_token_expires_at: params.accessTokenExpiresAt?.toISOString() ?? null,
      refresh_token_expires_at: params.refreshTokenExpiresAt?.toISOString() ?? null,
      status: "connected",
      updated_at: new Date().toISOString(),
    })
    .eq("id", params.connectionId)
    .eq("user_id", params.userId)

  if (error) throw new Error("broker_integration_credentials_update_failed")
}

export async function markBrokerConnectionReconnectRequired(
  supabase: SupabaseClient,
  connectionId: string,
  userId: string
): Promise<void> {
  await supabase
    .from("broker_integration_connections")
    .update({
      status: "reconnect_required",
      updated_at: new Date().toISOString(),
    })
    .eq("id", connectionId)
    .eq("user_id", userId)
}

export async function disconnectBrokerIntegrationById(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
    provider: BrokerIntegrationProvider
  }
): Promise<boolean> {
  const { data: row, error: loadError } = await supabase
    .from("broker_integration_connections")
    .select("id, status")
    .eq("id", params.connectionId)
    .eq("user_id", params.userId)
    .eq("provider", params.provider)
    .in("status", [...ACTIVE_STATUSES])
    .maybeSingle()

  if (loadError) throw new Error("broker_integration_disconnect_failed")
  if (!row) return false

  const { disableBrokerAccountsForConnection } = await import(
    "@/lib/integrations/brokerIntegrationAccounts"
  )
  await disableBrokerAccountsForConnection(supabase, {
    userId: params.userId,
    connectionId: row.id,
  })

  const now = new Date().toISOString()
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
    .eq("id", row.id)
    .select("id")
    .maybeSingle()

  if (error) throw new Error("broker_integration_disconnect_failed")
  return Boolean(data)
}

/** Service-role only: decrypt credentials for a specific connection. */
export async function loadBrokerIntegrationCredentialsForConnection(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
    provider: BrokerIntegrationProvider
  }
): Promise<IntegrationCredentialPayload | null> {
  const { data, error } = await supabase
    .from("broker_integration_connections")
    .select("status, credentials_ciphertext")
    .eq("id", params.connectionId)
    .eq("user_id", params.userId)
    .eq("provider", params.provider)
    .maybeSingle()

  if (error || !data || data.status !== "connected") return null
  const ciphertext = data.credentials_ciphertext
  if (!ciphertext || typeof ciphertext !== "string") return null
  return decryptIntegrationCredentials(ciphertext)
}
