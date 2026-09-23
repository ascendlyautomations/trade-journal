import type { SupabaseClient } from "@supabase/supabase-js"
import {
  getTradovateOAuthConfigForEnvironment,
  getTradovateRestBaseUrl,
  readServerDefaultTradovateApiEnvironment,
  TRADOVATE_REST_BASE_BY_ENV,
  type TradovateApiEnvironment,
} from "./tradovateOAuthEnv.ts"

export type TradovateEnvironmentHostSnapshot = {
  apiEnvironment: TradovateApiEnvironment
  authorizeHost: string
  tokenHost: string
  meHost: string
  restHost: string
  websocketHost: string
}

export function parseTradovateApiEnvironmentInput(
  value: string | null | undefined
): TradovateApiEnvironment | null {
  const raw = value?.trim().toLowerCase()
  if (raw === "demo" || raw === "live") return raw
  return null
}

export function tradovateEnvironmentHostSnapshot(
  apiEnvironment: TradovateApiEnvironment
): TradovateEnvironmentHostSnapshot {
  const config = getTradovateOAuthConfigForEnvironment(apiEnvironment)
  return {
    apiEnvironment,
    authorizeHost: new URL(config.authorizeUrl).host,
    tokenHost: new URL(config.tokenUrl).host,
    meHost: new URL(config.meUrl).host,
    restHost: new URL(getTradovateRestBaseUrl(apiEnvironment)).host,
    websocketHost: new URL(config.websocketUrl).host,
  }
}

export function assertTradovateRestHostMatchesEnvironment(params: {
  apiEnvironment: TradovateApiEnvironment
  restBaseUrl: string
}): void {
  const expected = TRADOVATE_REST_BASE_BY_ENV[params.apiEnvironment]
  const actual = params.restBaseUrl.replace(/\/$/, "")
  if (actual !== expected) {
    throw new Error("tradovate_environment_host_mismatch")
  }
}

export async function resolveTradovateApiEnvironmentForOAuth(params: {
  supabase: SupabaseClient
  userId: string
  oauthIntent: "connect_new" | "reconnect"
  targetConnectionId?: string | null
  requestedEnvironment?: TradovateApiEnvironment | null
}): Promise<TradovateApiEnvironment> {
  if (params.oauthIntent === "reconnect" && params.targetConnectionId) {
    const { data } = await params.supabase
      .from("broker_integration_connections")
      .select("api_environment")
      .eq("id", params.targetConnectionId)
      .eq("user_id", params.userId)
      .eq("provider", "tradovate")
      .maybeSingle()
    const stored = parseTradovateApiEnvironmentInput(
      data?.api_environment != null ? String(data.api_environment) : null
    )
    if (stored) return stored
  }

  if (params.requestedEnvironment) return params.requestedEnvironment

  return readServerDefaultTradovateApiEnvironment()
}

export function logTradovateEnvironmentSync(params: {
  connectionId: string
  storedEnvironment: TradovateApiEnvironment
  accountId?: string | null
}): void {
  const snap = tradovateEnvironmentHostSnapshot(params.storedEnvironment)
  console.info(
    [
      "[TradovateEnvironment]",
      `connectionId=${params.connectionId}`,
      `storedEnvironment=${params.storedEnvironment}`,
      `tokenEnvironment=${snap.apiEnvironment}`,
      `restEnvironment=${snap.restHost}`,
      `accountId=${params.accountId ?? "-"}`,
    ].join(" ")
  )
}
