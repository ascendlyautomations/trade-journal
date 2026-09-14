import { NextRequest, NextResponse } from "next/server"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { loadOwnedBrokerConnection } from "@/lib/integrations/brokerConnectionAccess"
import { createIntegrationOAuthState } from "@/lib/integrations/integrationOAuthState"
import {
  buildTradovateAuthorizationUrl,
  getTradovateOAuthConfig,
} from "@/lib/integrations/tradovate/tradovateOAuthEnv"
import {
  TRADOVATE_AUTHORIZE_HANDOFF_COOKIE,
  createTradovateAuthorizeHandoffValue,
  tradovateAuthorizeHandoffCookieOptions,
  verifyTradovateAuthorizeHandoffValue,
  type TradovateAuthorizeHandoffPayload,
} from "@/lib/integrations/tradovate/tradovateAuthorizeHandoff"
import { resolveAppUrl } from "@/lib/stripeServer"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

function loginRedirect(req: NextRequest): NextResponse {
  const base = resolveAppUrl(req)
  const returnTo = "/settings#trading-accounts"
  const login = new URL("/login", base)
  login.searchParams.set("redirect", returnTo)
  return NextResponse.redirect(login, { status: 302 })
}

function clearHandoffCookie(response: NextResponse): void {
  response.cookies.set(TRADOVATE_AUTHORIZE_HANDOFF_COOKIE, "", {
    ...tradovateAuthorizeHandoffCookieOptions(),
    maxAge: 0,
  })
}

async function resolveAuthorizeHandoff(
  request: NextRequest
): Promise<TradovateAuthorizeHandoffPayload | null> {
  const sessionUser = await getRouteUser(request)
  const cookieHandoff = request.cookies.get(TRADOVATE_AUTHORIZE_HANDOFF_COOKIE)?.value

  if (cookieHandoff) {
    try {
      return verifyTradovateAuthorizeHandoffValue(cookieHandoff)
    } catch {
      return null
    }
  }

  if (sessionUser?.id) {
    return {
      userId: sessionUser.id,
      oauthIntent: "connect_new",
      targetConnectionId: null,
    }
  }

  return null
}

async function beginTradovateOAuthRedirect(
  request: NextRequest,
  handoff: TradovateAuthorizeHandoffPayload
): Promise<NextResponse> {
  try {
    getTradovateOAuthConfig()
  } catch {
    console.error("[tradovate/authorize] oauth_config_missing")
    const res = NextResponse.json(
      { error: "Tradovate connection is temporarily unavailable." },
      { status: 503 }
    )
    clearHandoffCookie(res)
    return res
  }

  if (handoff.oauthIntent === "reconnect" && handoff.targetConnectionId) {
    const owned = await loadOwnedBrokerConnection(supabaseServiceRole, {
      userId: handoff.userId,
      connectionId: handoff.targetConnectionId,
      provider: "tradovate",
    })
    if (!owned) {
      const res = NextResponse.json(
        { error: "Tradovate connection not found." },
        { status: 404 }
      )
      clearHandoffCookie(res)
      return res
    }
  }

  let state: string
  try {
    const created = await createIntegrationOAuthState(supabaseServiceRole, {
      provider: "tradovate",
      userId: handoff.userId,
      redirectAfter: "/settings/integrations/tradovate",
      oauthIntent: handoff.oauthIntent,
      targetConnectionId: handoff.targetConnectionId,
    })
    state = created.state
  } catch (err) {
    console.error(
      "[tradovate/authorize] state_create_failed",
      err instanceof Error ? err.message : "unknown"
    )
    const res = NextResponse.json(
      { error: "Could not start Tradovate connection. Please try again." },
      { status: 500 }
    )
    clearHandoffCookie(res)
    return res
  }

  const authorizeUrl = buildTradovateAuthorizationUrl({ state })
  const response = NextResponse.redirect(authorizeUrl, { status: 302 })
  clearHandoffCookie(response)
  return response
}

export async function POST(request: NextRequest) {
  const user = await getRouteUser(request)
  if (!user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
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

  let body: { reconnectConnectionId?: string } = {}
  try {
    body = (await request.json()) as { reconnectConnectionId?: string }
  } catch {
    body = {}
  }

  const reconnectConnectionId = body.reconnectConnectionId?.trim() || null
  const oauthIntent = reconnectConnectionId ? "reconnect" : "connect_new"

  if (reconnectConnectionId) {
    const owned = await loadOwnedBrokerConnection(supabaseServiceRole, {
      userId: user.id,
      connectionId: reconnectConnectionId,
      provider: "tradovate",
    })
    if (!owned) {
      return NextResponse.json({ error: "Tradovate connection not found." }, { status: 404 })
    }
  }

  let handoffValue: string
  try {
    handoffValue = createTradovateAuthorizeHandoffValue({
      userId: user.id,
      oauthIntent,
      targetConnectionId: reconnectConnectionId,
    })
  } catch (err) {
    console.error(
      "[tradovate/authorize] handoff_create_failed",
      err instanceof Error ? err.message : "unknown"
    )
    return NextResponse.json(
      { error: "Could not start Tradovate connection. Please try again." },
      { status: 500 }
    )
  }

  const response = NextResponse.json({ ok: true })
  response.cookies.set(TRADOVATE_AUTHORIZE_HANDOFF_COOKIE, handoffValue, {
    ...tradovateAuthorizeHandoffCookieOptions(),
  })
  return response
}

export async function GET(request: NextRequest) {
  const handoff = await resolveAuthorizeHandoff(request)
  if (!handoff) {
    return loginRedirect(request)
  }

  return beginTradovateOAuthRedirect(request, handoff)
}
