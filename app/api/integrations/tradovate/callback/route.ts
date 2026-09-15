import { NextRequest, NextResponse } from "next/server"
import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  BrokerOAuthIdentityMismatchError,
  persistTradovateConnectionAfterOAuth,
} from "@/lib/integrations/brokerIntegrationConnection"
import { consumeIntegrationOAuthState } from "@/lib/integrations/integrationOAuthState"
import {
  buildTradovateIntegrationResultUrl,
  parseTradovateCallbackQuery,
  type TradovateCallbackOutcome,
} from "@/lib/integrations/tradovate/tradovateOAuthCallback"
import { getTradovateOAuthConfig } from "@/lib/integrations/tradovate/tradovateOAuthEnv"
import {
  exchangeTradovateAuthorizationCode,
  fetchTradovateMeProfile,
  parseTradovateIdTokenSubject,
} from "@/lib/integrations/tradovate/tradovateTokenExchange"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

function redirectOutcome(req: NextRequest, outcome: TradovateCallbackOutcome) {
  const target = buildTradovateIntegrationResultUrl(req, outcome)
  return NextResponse.redirect(target, { status: 302 })
}

export async function GET(request: NextRequest) {
  const query = parseTradovateCallbackQuery(request.nextUrl.searchParams)

  if (query.oauthError) {
    console.info("[tradovate/callback] oauth_error", {
      error: query.oauthError,
      hasDescription: Boolean(query.oauthErrorDescription),
    })
    return redirectOutcome(request, { kind: "error", reason: "denied" })
  }

  if (!query.state) {
    return redirectOutcome(request, { kind: "error", reason: "invalid_state" })
  }

  let boundUser: Awaited<ReturnType<typeof consumeIntegrationOAuthState>> = null
  try {
    boundUser = await consumeIntegrationOAuthState(supabaseServiceRole, {
      provider: "tradovate",
      state: query.state,
    })
  } catch (err) {
    console.error(
      "[tradovate/callback] state_validation_failed",
      err instanceof Error ? err.message : "unknown"
    )
    return redirectOutcome(request, { kind: "error", reason: "server" })
  }

  if (!boundUser) {
    return redirectOutcome(request, { kind: "error", reason: "invalid_state" })
  }

  if (!query.code) {
    return redirectOutcome(request, { kind: "error", reason: "missing_code" })
  }

  try {
    getTradovateOAuthConfig()
  } catch {
    console.error("[tradovate/callback] oauth_config_missing")
    return redirectOutcome(request, { kind: "error", reason: "server" })
  }

  const exchange = await exchangeTradovateAuthorizationCode(query.code)
  if (!exchange.ok) {
    console.info("[tradovate/callback] token_exchange_failed", {
      reason: exchange.reason,
      oauthError: exchange.oauthError ?? null,
    })
    return redirectOutcome(request, { kind: "error", reason: "token_exchange" })
  }

  const tokens = exchange.tokens
  const config = getTradovateOAuthConfig()
  const nowMs = Date.now()
  const accessExpiresAt =
    typeof tokens.expires_in === "number" && tokens.expires_in > 0
      ? new Date(nowMs + tokens.expires_in * 1000)
      : null
  const refreshExpiresAt =
    typeof tokens.refresh_token_expires_in === "number" &&
    tokens.refresh_token_expires_in > 0
      ? new Date(nowMs + tokens.refresh_token_expires_in * 1000)
      : null

  let providerUserId = parseTradovateIdTokenSubject(tokens.id_token)
  let providerDisplayName: string | null = null
  const me = await fetchTradovateMeProfile(tokens.access_token)
  if (me?.userId != null && !providerUserId) {
    providerUserId = String(me.userId)
  }
  if (me?.fullName?.trim()) {
    providerDisplayName = me.fullName.trim()
  }

  let connectionId: string
  try {
    const persisted = await persistTradovateConnectionAfterOAuth(supabaseServiceRole, {
      userId: boundUser.user_id,
      providerUserId,
      providerDisplayName,
      credentials: {
        kind: "tradovate",
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token ?? null,
        token_type: tokens.token_type ?? null,
      },
      accessTokenExpiresAt: accessExpiresAt,
      refreshTokenExpiresAt: refreshExpiresAt,
      apiEnvironment: config.apiEnvironment,
      oauthIntent: boundUser.oauth_intent,
      targetConnectionId: boundUser.target_connection_id,
    })
    connectionId = persisted.connectionId
  } catch (err) {
    if (err instanceof BrokerOAuthIdentityMismatchError) {
      return redirectOutcome(request, { kind: "error", reason: "identity_mismatch" })
    }
    console.error(
      "[tradovate/callback] connection_persist_failed",
      err instanceof Error ? err.message : "unknown"
    )
    return redirectOutcome(request, { kind: "error", reason: "server" })
  }

  console.info("[tradovate/callback] connection_established", {
    userId: boundUser.user_id,
    hasProviderUserId: Boolean(providerUserId),
  })

  const { runTradovateAccountDiscovery } = await import(
    "@/lib/integrations/tradovate/runTradovateAccountDiscovery"
  )
  void runTradovateAccountDiscovery(
    supabaseServiceRole,
    boundUser.user_id,
    connectionId
  ).catch((err) => {
    console.error(
      "[tradovate/callback] account_discovery_failed",
      err instanceof Error ? err.message : "unknown"
    )
  })

  return redirectOutcome(request, { kind: "success" })
}
