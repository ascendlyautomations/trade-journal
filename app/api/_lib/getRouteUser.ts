import { createClient } from "@supabase/supabase-js"
import { createServerClient } from "@supabase/ssr"
import { cookies } from "next/headers"
import type { User } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"

const supabaseService = createClient<Database>(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!,
  { auth: { persistSession: false, autoRefreshToken: false } }
)

export type RouteAuthFailure = {
  code: string | null
  message: string | null
  status: number | null
}

function describeAuthFailure(error: {
  code?: string
  message?: string
  status?: number
} | null): RouteAuthFailure | null {
  if (!error) return null
  return {
    code: error.code ?? null,
    message: error.message ?? null,
    status: error.status ?? null,
  }
}

/**
 * Resolves the current Supabase user from the Authorization bearer token, then cookies.
 * Browser sessions live in localStorage, so cookie auth is empty unless a server client wrote them.
 * Bearer validation stays `auth.getUser()` — a signed JWT whose session row is gone is rejected.
 */
export async function getRouteUserAuth(req: Request): Promise<{
  user: User | null
  authError: RouteAuthFailure | null
}> {
  const authHeader = req.headers.get("authorization") || ""
  const bearer = authHeader.startsWith("Bearer ")
    ? authHeader.slice("Bearer ".length).trim()
    : ""

  let authError: RouteAuthFailure | null = null

  if (bearer) {
    const { data: tokenData, error: tokenErr } =
      await supabaseService.auth.getUser(bearer)
    if (!tokenErr && tokenData.user) return { user: tokenData.user, authError: null }
    authError = describeAuthFailure(tokenErr)
    if (authError) {
      console.error("[auth] getUser rejected bearer session", {
        operation: "getRouteUser",
        code: authError.code,
        message: authError.message,
        status: authError.status,
      })
    }
  }

  const cookieStore = await cookies()
  const supabaseAuth = createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get: (name) => cookieStore.get(name)?.value,
      },
    }
  )

  const {
    data: { user: cookieUser },
    error: cookieErr,
  } = await supabaseAuth.auth.getUser()

  if (cookieUser) return { user: cookieUser, authError: null }

  return {
    user: null,
    authError: authError ?? describeAuthFailure(cookieErr),
  }
}

export async function getRouteUser(req: Request): Promise<User | null> {
  return (await getRouteUserAuth(req)).user
}

export { supabaseService as supabaseServiceRole }
