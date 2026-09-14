import type { SupabaseClient } from "@supabase/supabase-js"
import {
  decryptIntegrationCredentials,
  encryptIntegrationCredentials,
  type IntegrationCredentialPayload,
} from "@/lib/integrations/credentialEncryption"
import { upsertTradovateConnection } from "@/lib/integrations/brokerIntegrationConnection"
import type { TradovateApiEnvironment } from "@/lib/integrations/tradovate/tradovateOAuthEnv"
import { getTradovateRestBaseUrl } from "@/lib/integrations/tradovate/tradovateOAuthEnv"
import {
  credentialsFromRefreshTokens,
  refreshTradovateAccessToken,
  tokenExpiryDates,
} from "@/lib/integrations/tradovate/tradovateTokenRefresh"
import { runTradovateTokenRefreshSingleFlight } from "@/lib/integrations/tradovate/tradovateTokenRefreshFlight"

const ACCESS_TOKEN_SKEW_MS = 60_000

type ConnectedTradovateConnection = {
  id: string
  user_id: string
  provider_user_id: string | null
  credentials_ciphertext: string
  access_token_expires_at: string | null
  api_environment: TradovateApiEnvironment
}

export type TradovateApiClientError =
  | "not_connected"
  | "reconnect_required"
  | "provider_unavailable"
  | "unauthorized"

export class TradovateApiError extends Error {
  constructor(
    readonly code: TradovateApiClientError,
    message?: string
  ) {
    super(message ?? code)
    this.name = "TradovateApiError"
  }
}

async function loadConnectedConnection(
  supabase: SupabaseClient,
  userId: string
): Promise<ConnectedTradovateConnection | null> {
  const { data, error } = await supabase
    .from("broker_integration_connections")
    .select(
      "id, user_id, provider_user_id, status, credentials_ciphertext, access_token_expires_at, api_environment"
    )
    .eq("user_id", userId)
    .eq("provider", "tradovate")
    .maybeSingle()

  if (error || !data) return null
  if (data.status !== "connected") return null
  if (!data.credentials_ciphertext) return null
  if (data.api_environment !== "demo" && data.api_environment !== "live") return null

  return data as ConnectedTradovateConnection
}

async function markReconnectRequired(
  supabase: SupabaseClient,
  userId: string
): Promise<void> {
  await supabase
    .from("broker_integration_connections")
    .update({
      status: "reconnect_required",
      updated_at: new Date().toISOString(),
    })
    .eq("user_id", userId)
    .eq("provider", "tradovate")
}

function accessTokenExpired(expiresAtIso: string | null): boolean {
  if (!expiresAtIso) return false
  const expiresMs = new Date(expiresAtIso).getTime()
  if (Number.isNaN(expiresMs)) return false
  return expiresMs - ACCESS_TOKEN_SKEW_MS <= Date.now()
}

async function persistRefreshedCredentials(
  supabase: SupabaseClient,
  connection: ConnectedTradovateConnection,
  credentials: IntegrationCredentialPayload,
  accessTokenExpiresAt: Date | null,
  refreshTokenExpiresAt: Date | null
): Promise<void> {
  await upsertTradovateConnection(supabase, {
    userId: connection.user_id,
    providerUserId: connection.provider_user_id,
    credentials,
    accessTokenExpiresAt,
    refreshTokenExpiresAt,
    apiEnvironment: connection.api_environment,
  })
}

async function ensureValidAccessToken(
  supabase: SupabaseClient,
  connection: ConnectedTradovateConnection
): Promise<string> {
  let credentials = decryptIntegrationCredentials(connection.credentials_ciphertext)

  if (!accessTokenExpired(connection.access_token_expires_at)) {
    return credentials.access_token
  }

  const refreshed = await runTradovateTokenRefreshSingleFlight(connection.user_id, async () => {
    const current = decryptIntegrationCredentials(connection.credentials_ciphertext)
    if (!current.refresh_token?.trim()) {
      await markReconnectRequired(supabase, connection.user_id)
      return false
    }

    const result = await refreshTradovateAccessToken(current.refresh_token)
    if (!result.ok) {
      await markReconnectRequired(supabase, connection.user_id)
      return false
    }

    const nextCredentials = credentialsFromRefreshTokens(result.tokens)
    const expiries = tokenExpiryDates(result.tokens)
    await persistRefreshedCredentials(
      supabase,
      connection,
      nextCredentials,
      expiries.accessTokenExpiresAt,
      expiries.refreshTokenExpiresAt
    )
    return true
  })

  if (!refreshed) {
    throw new TradovateApiError("reconnect_required")
  }

  const reloaded = await loadConnectedConnection(supabase, connection.user_id)
  if (!reloaded) throw new TradovateApiError("not_connected")
  credentials = decryptIntegrationCredentials(reloaded.credentials_ciphertext)
  return credentials.access_token
}

export async function tradovateAuthedJsonRequest<T>(
  supabase: SupabaseClient,
  userId: string,
  path: string,
  init?: { method?: "GET" | "POST"; retried?: boolean }
): Promise<T> {
  const connection = await loadConnectedConnection(supabase, userId)
  if (!connection) {
    throw new TradovateApiError("not_connected")
  }

  const accessToken = await ensureValidAccessToken(supabase, connection)
  const base = getTradovateRestBaseUrl(connection.api_environment)
  const url = `${base}${path.startsWith("/") ? path : `/${path}`}`

  let response: Response
  try {
    response = await fetch(url, {
      method: init?.method ?? "GET",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: init?.method === "POST" ? "{}" : undefined,
    })
  } catch {
    throw new TradovateApiError("provider_unavailable")
  }

  if (response.status === 401 && !init?.retried) {
    const current = decryptIntegrationCredentials(connection.credentials_ciphertext)
    if (!current.refresh_token?.trim()) {
      await markReconnectRequired(supabase, userId)
      throw new TradovateApiError("reconnect_required")
    }

    const refreshed = await runTradovateTokenRefreshSingleFlight(userId, async () => {
      const result = await refreshTradovateAccessToken(current.refresh_token!)
      if (!result.ok) {
        await markReconnectRequired(supabase, userId)
        return false
      }
      const nextCredentials = credentialsFromRefreshTokens(result.tokens)
      const expiries = tokenExpiryDates(result.tokens)
      await persistRefreshedCredentials(
        supabase,
        connection,
        nextCredentials,
        expiries.accessTokenExpiresAt,
        expiries.refreshTokenExpiresAt
      )
      return true
    })

    if (!refreshed) throw new TradovateApiError("reconnect_required")
    return tradovateAuthedJsonRequest(supabase, userId, path, {
      ...init,
      retried: true,
    })
  }

  if (!response.ok) {
    if (response.status === 401) throw new TradovateApiError("unauthorized")
    throw new TradovateApiError("provider_unavailable")
  }

  try {
    return (await response.json()) as T
  } catch {
    throw new TradovateApiError("provider_unavailable")
  }
}

export async function fetchTradovateAccountListRaw(
  supabase: SupabaseClient,
  userId: string
): Promise<unknown[]> {
  const body = await tradovateAuthedJsonRequest<unknown>(supabase, userId, "/v1/account/list")
  if (!Array.isArray(body)) {
    throw new TradovateApiError("provider_unavailable")
  }
  return body
}
