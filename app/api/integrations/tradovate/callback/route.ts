import { NextRequest, NextResponse } from "next/server"
import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { consumeIntegrationOAuthState } from "@/lib/integrations/integrationOAuthState"
import {
  buildTradovateIntegrationResultUrl,
  parseTradovateCallbackQuery,
  type TradovateCallbackOutcome,
} from "@/lib/integrations/tradovate/tradovateOAuthCallback"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

function redirectOutcome(req: NextRequest, outcome: TradovateCallbackOutcome) {
  const target = buildTradovateIntegrationResultUrl(req, outcome)
  return NextResponse.redirect(target, { status: 302 })
}

/**
 * Tradovate OAuth redirect URI (register in Tradovate developer portal):
 *   https://www.tradetraxs.com/api/integrations/tradovate/callback
 *
 * Next phase: authorization code → server-side token exchange → encrypted storage → sync.
 */
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

  let boundUser: { user_id: string } | null = null
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

  // Do not log authorization codes. Token exchange is a follow-up phase.
  console.info("[tradovate/callback] authorization_code_received", {
    userId: boundUser.user_id,
    codeLength: query.code.length,
  })

  // Phase 2: await exchangeTradovateAuthorizationCode({ code: query.code, userId: boundUser.user_id })

  return redirectOutcome(request, { kind: "success" })
}
