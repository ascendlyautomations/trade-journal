import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { storeAppleAuthorizationCodeForUser } from "@/lib/appleSignInRevocation"

export const runtime = "nodejs"

type Body = {
  authorizationCode?: string
}

/**
 * Stores an Apple refresh token for future account-deletion revocation.
 * Called by native iOS after Supabase Sign in with Apple succeeds.
 * Never returns token material to the client.
 */
export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let body: Body
  try {
    body = (await req.json()) as Body
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  const authorizationCode = body.authorizationCode?.trim()
  if (!authorizationCode) {
    return Response.json({ error: "Missing authorizationCode" }, { status: 400 })
  }

  try {
    const result = await storeAppleAuthorizationCodeForUser(
      supabaseServiceRole,
      user.id,
      authorizationCode
    )
    return Response.json({ ok: true, stored: result.stored })
  } catch {
    return Response.json({ ok: true, stored: false })
  }
}
