import { NextRequest, NextResponse } from "next/server"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
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

async function resolveAuthorizeUserId(request: NextRequest): Promise<string | null> {
  const sessionUser = await getRouteUser(request)
  if (sessionUser?.id) return sessionUser.id

  const handoff = request.cookies.get(TRADOVATE_AUTHORIZE_HANDOFF_COOKIE)?.value
  if (!handoff) return null

  try {
    return verifyTradovateAuthorizeHandoffValue(handoff)
  } catch {
    return null
  }
}

async function beginTradovateOAuthRedirect(
  request: NextRequest,
  userId: string
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

  let state: string
  try {
    const created = await createIntegrationOAuthState(supabaseServiceRole, {
      provider: "tradovate",
      userId,
      redirectAfter: "/settings/integrations/tradovate",
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

/**
 * POST: bind a short-lived httpOnly cookie after Bearer auth (localStorage sessions).
 * GET: top-level entry — cookie or cookie session → 302 to Tradovate OAuth (document navigation).
 */
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

  let handoffValue: string
  try {
    handoffValue = createTradovateAuthorizeHandoffValue(user.id)
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
  const userId = await resolveAuthorizeUserId(request)
  if (!userId) {
    return loginRedirect(request)
  }

  return beginTradovateOAuthRedirect(request, userId)
}
