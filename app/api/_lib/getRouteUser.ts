import { createClient } from "@supabase/supabase-js"
import { createServerClient } from "@supabase/ssr"
import { cookies } from "next/headers"
import type { User } from "@supabase/supabase-js"

const supabaseService = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

/**
 * Resolves the current Supabase user from request cookies, with optional Authorization: Bearer fallback
 * (same pattern as `app/api/create-checkout-session/route.ts`).
 *
 * Prefer Bearer when present — browser sessions use localStorage, so cookie auth often
 * does an empty round-trip before the Bearer fallback.
 */
export async function getRouteUser(req: Request): Promise<User | null> {
  const authHeader = req.headers.get("authorization") || ""
  const bearer = authHeader.startsWith("Bearer ")
    ? authHeader.slice("Bearer ".length).trim()
    : ""

  if (bearer) {
    const { data: tokenData, error: tokenErr } =
      await supabaseService.auth.getUser(bearer)
    if (!tokenErr && tokenData.user) return tokenData.user
  }

  const cookieStore = await cookies()
  const supabaseAuth = createServerClient(
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
  } = await supabaseAuth.auth.getUser()

  return cookieUser ?? null
}

export { supabaseService as supabaseServiceRole }
