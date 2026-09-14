import { NextRequest, NextResponse } from "next/server"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { createIntegrationOAuthState } from "@/lib/integrations/integrationOAuthState"
import {
  buildTradovateAuthorizationUrl,
  getTradovateOAuthConfig,
} from "@/lib/integrations/tradovate/tradovateOAuthEnv"
import { resolveAppUrl } from "@/lib/stripeServer"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

function loginRedirect(req: NextRequest): NextResponse {
  const base = resolveAppUrl(req)
  const returnTo = "/settings/integrations/tradovate"
  const login = new URL("/login", base)
  login.searchParams.set("redirect", returnTo)
  return NextResponse.redirect(login, { status: 302 })
}

/**
 * Starts Tradovate OAuth for the signed-in TradeTraxs user.
 * Browser clients with localStorage sessions should call with Authorization: Bearer and redirect: manual.
 */
export async function GET(request: NextRequest) {
  const user = await getRouteUser(request)
  if (!user?.id) {
    return loginRedirect(request)
  }

  try {
    getTradovateOAuthConfig()
  } catch {
    console.error("[tradovate/authorize] oauth_config_missing")
    return NextResponse.json(
      { error: "Tradovate connection is temporarily unavailable." },
      { status: 503 }
    )
  }

  let state: string
  try {
    const created = await createIntegrationOAuthState(supabaseServiceRole, {
      provider: "tradovate",
      userId: user.id,
      redirectAfter: "/settings/integrations/tradovate",
    })
    state = created.state
  } catch (err) {
    console.error(
      "[tradovate/authorize] state_create_failed",
      err instanceof Error ? err.message : "unknown"
    )
    return NextResponse.json(
      { error: "Could not start Tradovate connection. Please try again." },
      { status: 500 }
    )
  }

  const authorizeUrl = buildTradovateAuthorizationUrl({ state })
  return NextResponse.redirect(authorizeUrl, { status: 302 })
}
