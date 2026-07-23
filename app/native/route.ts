import { createServerClient } from "@supabase/ssr"
import { cookies } from "next/headers"
import { redirectToPath } from "@/lib/requestOrigin"

export const dynamic = "force-dynamic"

/**
 * Native cold-start entry (Capacitor server.url → /native).
 * Sets tt_native cookie (used by NativeHomeRedirect) and redirects:
 * authenticated → /dashboard, else → /login.
 * Web marketing homepage `/` is unchanged.
 *
 * Uses a relative Location so the client keeps its request host
 * (LAN IP on physical devices — never rewrite to localhost).
 */
export async function GET() {
  const cookieStore = await cookies()
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll()
        },
        setAll() {
          // Read-only during redirect; session refresh not required here.
        },
      },
    }
  )

  const {
    data: { user },
  } = await supabase.auth.getUser()

  const response = redirectToPath(user ? "/dashboard" : "/login")

  response.cookies.set("tt_native", "1", {
    path: "/",
    sameSite: "lax",
    maxAge: 60 * 60 * 24 * 400,
    httpOnly: false,
  })

  return response
}
