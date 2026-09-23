import { NextRequest, NextResponse } from "next/server"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { loadOwnedBrokerConnection } from "@/lib/integrations/brokerConnectionAccess"
import { createIntegrationOAuthState } from "@/lib/integrations/integrationOAuthState"
import {
  parseTradovateApiEnvironmentInput,
  resolveTradovateApiEnvironmentForOAuth,
} from "@/lib/integrations/tradovate/tradovateApiEnvironment"
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
import {
  buildNativeTradovateAuthorizeJsonResponse,
  buildWebTradovateAuthorizeJsonResponse,
  isNativeTradovateAuthorizeRequest,
  parseTradovateAuthorizePostBody,
  TRADOVATE_NATIVE_OAUTH_CLIENT_HEADER,
  TRADOVATE_NATIVE_OAUTH_REDIRECT_AFTER,
} from "@/lib/integrations/tradovate/tradovateAuthorizePost"
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

async function createTradovateAuthorizeUrlForHandoff(
  handoff: TradovateAuthorizeHandoffPayload,
  redirectAfter: string,
  apiEnvironment: Awaited<
    ReturnType<typeof resolveTradovateApiEnvironmentForOAuth>
  >
): Promise<{ ok: true; authorizeUrl: string } | { ok: false; response: NextResponse }> {
  try {
    getTradovateOAuthConfig()
  } catch {
    console.error("[tradovate/authorize] oauth_config_missing")
    return {
      ok: false,
      response: NextResponse.json(
        { error: "Tradovate connection is temporarily unavailable." },
        { status: 503 }
      ),
    }
  }

  if (handoff.oauthIntent === "reconnect" && handoff.targetConnectionId) {
    const owned = await loadOwnedBrokerConnection(supabaseServiceRole, {
      userId: handoff.userId,
      connectionId: handoff.targetConnectionId,
      provider: "tradovate",
    })
    if (!owned) {
      return {
        ok: false,
        response: NextResponse.json(
          { error: "Tradovate connection not found." },
          { status: 404 }
        ),
      }
    }
  }

  let state: string
  try {
    const created = await createIntegrationOAuthState(supabaseServiceRole, {
      provider: "tradovate",
      userId: handoff.userId,
      redirectAfter,
      oauthIntent: handoff.oauthIntent,
      targetConnectionId: handoff.targetConnectionId,
      apiEnvironment,
    })
    state = created.state
  } catch (err) {
    console.error(
      "[tradovate/authorize] state_create_failed",
      err instanceof Error ? err.message : "unknown"
    )
    return {
      ok: false,
      response: NextResponse.json(
        { error: "Could not start Tradovate connection. Please try again." },
        { status: 500 }
      ),
    }
  }

  return { ok: true, authorizeUrl: buildTradovateAuthorizationUrl({ state }) }
}

async function beginTradovateOAuthRedirect(
  request: NextRequest,
  handoff: TradovateAuthorizeHandoffPayload
): Promise<NextResponse> {
  const apiEnvironment = await resolveTradovateApiEnvironmentForOAuth({
    supabase: supabaseServiceRole,
    userId: handoff.userId,
    oauthIntent: handoff.oauthIntent,
    targetConnectionId: handoff.targetConnectionId,
    requestedEnvironment: null,
  })
  const created = await createTradovateAuthorizeUrlForHandoff(
    handoff,
    "/settings/integrations/tradovate",
    apiEnvironment
  )
  if (!created.ok) {
    const res = created.response
    clearHandoffCookie(res)
    return res
  }

  const response = NextResponse.redirect(created.authorizeUrl, { status: 302 })
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

  let rawBody: unknown = {}
  try {
    rawBody = await request.json()
  } catch {
    rawBody = {}
  }
  const body = parseTradovateAuthorizePostBody(rawBody)

  const reconnectConnectionId = body.reconnectConnectionId?.trim() || null
  const oauthIntent = reconnectConnectionId ? "reconnect" : "connect_new"
  const nativeClient = isNativeTradovateAuthorizeRequest(
    body,
    request.headers.get(TRADOVATE_NATIVE_OAUTH_CLIENT_HEADER)
  )

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

  const apiEnvironment = await resolveTradovateApiEnvironmentForOAuth({
    supabase: supabaseServiceRole,
    userId: user.id,
    oauthIntent,
    targetConnectionId: reconnectConnectionId,
    requestedEnvironment:
      oauthIntent === "connect_new"
        ? parseTradovateApiEnvironmentInput(body.apiEnvironment)
        : null,
  })

  if (nativeClient) {
    const handoff: TradovateAuthorizeHandoffPayload = {
      userId: user.id,
      oauthIntent,
      targetConnectionId: reconnectConnectionId,
    }
    const created = await createTradovateAuthorizeUrlForHandoff(
      handoff,
      TRADOVATE_NATIVE_OAUTH_REDIRECT_AFTER,
      apiEnvironment
    )
    if (!created.ok) {
      return created.response
    }
    console.info("[tradovate/authorize] post_contract=native", {
      hasAuthorizeUrl: true,
    })
    return NextResponse.json(
      buildNativeTradovateAuthorizeJsonResponse(created.authorizeUrl)
    )
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

  console.info("[tradovate/authorize] post_contract=web_handoff")
  const response = NextResponse.json(buildWebTradovateAuthorizeJsonResponse())
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
