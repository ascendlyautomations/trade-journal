import type { SupabaseClient } from "@supabase/supabase-js"
import {
  decryptIntegrationCredentials,
  isTradovateIntegrationCredentials,
  type IntegrationCredentialPayload,
  type TradovateIntegrationCredentials,
} from "@/lib/integrations/credentialEncryption"
import {
  markBrokerConnectionReconnectRequired,
  updateBrokerConnectionCredentials,
} from "@/lib/integrations/brokerIntegrationConnection"
import { loadOwnedBrokerConnection } from "@/lib/integrations/brokerConnectionAccess"
import type { TradovateApiEnvironment } from "@/lib/integrations/tradovate/tradovateOAuthEnv"
import { getTradovateRestBaseUrl } from "@/lib/integrations/tradovate/tradovateOAuthEnv"
import {
  credentialsFromRefreshTokens,
  refreshTradovateAccessToken,
  tokenExpiryDates,
} from "@/lib/integrations/tradovate/tradovateTokenRefresh"
import { runTradovateTokenRefreshSingleFlight } from "@/lib/integrations/tradovate/tradovateTokenRefreshFlight"

const ACCESS_TOKEN_SKEW_MS = 60_000

function requireTradovateCredentials(
  payload: IntegrationCredentialPayload
): TradovateIntegrationCredentials {
  if (!isTradovateIntegrationCredentials(payload)) {
    throw new Error("tradovate_connection_credentials_invalid")
  }
  return payload
}

type ConnectedTradovateConnection = {
  id: string
  user_id: string
  provider_user_id: string | null
  status: string
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
    message?: string,
    readonly httpStatus?: number
  ) {
    super(message ?? code)
    this.name = "TradovateApiError"
  }
}

function isUsableConnectionStatus(status: string): boolean {
  return status === "connected" || status === "reconnect_required"
}

/**
 * Load a Tradovate connection that still has credentials we can try.
 * `reconnect_required` must not hard-block: production can leave valid
 * access/refresh tokens in place after a transient refresh failure.
 */
async function loadConnectedConnection(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string
): Promise<ConnectedTradovateConnection | null> {
  const { data, error } = await supabase
    .from("broker_integration_connections")
    .select(
      "id, user_id, provider_user_id, status, credentials_ciphertext, access_token_expires_at, api_environment"
    )
    .eq("id", connectionId)
    .eq("user_id", userId)
    .eq("provider", "tradovate")
    .maybeSingle()

  if (error || !data) return null
  if (!isUsableConnectionStatus(String(data.status))) return null
  if (!data.credentials_ciphertext) return null
  if (data.api_environment !== "demo" && data.api_environment !== "live") return null

  return data as ConnectedTradovateConnection
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
  await updateBrokerConnectionCredentials(supabase, {
    connectionId: connection.id,
    userId: connection.user_id,
    credentials,
    accessTokenExpiresAt,
    refreshTokenExpiresAt,
  })
}

/** Restore connected when we successfully use existing credentials after a false reconnect_required. */
async function healReconnectRequiredStatus(
  supabase: SupabaseClient,
  connection: ConnectedTradovateConnection
): Promise<void> {
  if (connection.status !== "reconnect_required") return
  await supabase
    .from("broker_integration_connections")
    .update({
      status: "connected",
      updated_at: new Date().toISOString(),
    })
    .eq("id", connection.id)
    .eq("user_id", connection.user_id)
    .eq("status", "reconnect_required")
}

type AuthRecovery = "retry" | "reconnect_required" | "provider_unavailable"

/**
 * After a 401 (or forced refresh): reload canonical credentials, reuse a
 * concurrent refresh if one already landed, otherwise refresh once.
 * Never mark reconnect_required while an unexpired access token is still current.
 */
async function recoverAccessTokenAfterChallenge(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string,
  failedAccessToken: string
): Promise<AuthRecovery> {
  const recovered = await runTradovateTokenRefreshSingleFlight(connectionId, async () => {
    const latest = await loadConnectedConnection(supabase, userId, connectionId)
    if (!latest) return false

    const current = requireTradovateCredentials(
      decryptIntegrationCredentials(latest.credentials_ciphertext)
    )

    // Another request already persisted rotated credentials — reuse them.
    if (current.access_token !== failedAccessToken) {
      await healReconnectRequiredStatus(supabase, latest)
      return true
    }

    const expired = accessTokenExpired(latest.access_token_expires_at)

    if (!current.refresh_token?.trim()) {
      if (expired) {
        await markBrokerConnectionReconnectRequired(supabase, connectionId, userId)
      }
      return false
    }

    const result = await refreshTradovateAccessToken(current.refresh_token)
    if (!result.ok) {
      // Only permanently lock when the access token is actually expired (or
      // missing refresh) and Tradovate rejected refresh. A 401 on a still-valid
      // access token (e.g. concurrent fillFee deps) must not burn the connection.
      if (result.reason === "no_refresh_token") {
        await markBrokerConnectionReconnectRequired(supabase, connectionId, userId)
      } else if (result.reason === "oauth_error" && expired) {
        await markBrokerConnectionReconnectRequired(supabase, connectionId, userId)
      }
      return false
    }

    const nextCredentials = credentialsFromRefreshTokens(result.tokens)
    const expiries = tokenExpiryDates(result.tokens)
    await persistRefreshedCredentials(
      supabase,
      latest,
      nextCredentials,
      expiries.accessTokenExpiresAt,
      expiries.refreshTokenExpiresAt
    )
    return true
  })

  if (recovered) return "retry"

  const latest = await loadConnectedConnection(supabase, userId, connectionId)
  if (!latest) return "reconnect_required"
  if (latest.status === "reconnect_required") return "reconnect_required"
  return "provider_unavailable"
}

async function ensureValidAccessToken(
  supabase: SupabaseClient,
  connection: ConnectedTradovateConnection
): Promise<string> {
  let credentials = requireTradovateCredentials(
    decryptIntegrationCredentials(connection.credentials_ciphertext)
  )

  if (!accessTokenExpired(connection.access_token_expires_at)) {
    await healReconnectRequiredStatus(supabase, connection)
    return credentials.access_token
  }

  const recovery = await recoverAccessTokenAfterChallenge(
    supabase,
    connection.user_id,
    connection.id,
    credentials.access_token
  )
  if (recovery === "reconnect_required") {
    throw new TradovateApiError("reconnect_required")
  }
  if (recovery === "provider_unavailable") {
    throw new TradovateApiError("provider_unavailable")
  }

  const reloaded = await loadConnectedConnection(
    supabase,
    connection.user_id,
    connection.id
  )
  if (!reloaded) throw new TradovateApiError("not_connected")
  credentials = requireTradovateCredentials(
    decryptIntegrationCredentials(reloaded.credentials_ciphertext)
  )
  return credentials.access_token
}

export async function tradovateAuthedJsonRequest<T>(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string,
  path: string,
  init?: { method?: "GET" | "POST"; retried?: boolean }
): Promise<T> {
  const owned = await loadOwnedBrokerConnection(supabase, {
    userId,
    connectionId,
    provider: "tradovate",
  })
  if (!owned || !isUsableConnectionStatus(owned.status)) {
    throw new TradovateApiError("not_connected")
  }

  const connection = await loadConnectedConnection(supabase, userId, connectionId)
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
    const recovery = await recoverAccessTokenAfterChallenge(
      supabase,
      userId,
      connectionId,
      accessToken
    )
    if (recovery === "reconnect_required") {
      throw new TradovateApiError("reconnect_required")
    }
    if (recovery === "provider_unavailable") {
      throw new TradovateApiError("provider_unavailable")
    }
    return tradovateAuthedJsonRequest(supabase, userId, connectionId, path, {
      ...init,
      retried: true,
    })
  }

  if (!response.ok) {
    if (response.status === 401) {
      throw new TradovateApiError("unauthorized", undefined, response.status)
    }
    throw new TradovateApiError(
      "provider_unavailable",
      undefined,
      response.status
    )
  }

  try {
    return (await response.json()) as T
  } catch {
    throw new TradovateApiError("provider_unavailable")
  }
}

export async function fetchTradovateAccountListRaw(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string
): Promise<unknown[]> {
  const body = await tradovateAuthedJsonRequest<unknown>(
    supabase,
    userId,
    connectionId,
    "/v1/account/list"
  )
  if (!Array.isArray(body)) {
    throw new TradovateApiError("provider_unavailable")
  }
  return body
}
