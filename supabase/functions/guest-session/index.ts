import "jsr:@supabase/functions-js/edge-runtime.d.ts"

const SHOWCASE_USER_ID = "7063f0d0-c701-4b1a-82f8-e4c360d4d2ec"

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  })
}

function payload(accessToken: string): Record<string, unknown> | null {
  const parts = accessToken.split(".")
  if (parts.length < 2) return null
  const padded = parts[1].replace(/-/g, "+").replace(/_/g, "/")
  const pad = padded + "=".repeat((4 - (padded.length % 4)) % 4)
  try {
    return JSON.parse(atob(pad))
  } catch {
    return null
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405)

  const supabaseUrl = Deno.env.get("SUPABASE_URL")
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")
  if (!supabaseUrl || !serviceKey || !anonKey) return json({ error: "unavailable" }, 500)

  const adminHeaders = {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
  }

  const userResponse = await fetch(`${supabaseUrl}/auth/v1/admin/users/${SHOWCASE_USER_ID}`, {
    headers: adminHeaders,
  })
  if (!userResponse.ok) return json({ error: "showcase_unavailable" }, 500)
  const user = await userResponse.json()
  const email = typeof user.email === "string" ? user.email : ""
  if (!email) return json({ error: "showcase_unavailable" }, 500)

  const linkResponse = await fetch(`${supabaseUrl}/auth/v1/admin/generate_link`, {
    method: "POST",
    headers: adminHeaders,
    body: JSON.stringify({ type: "magiclink", email }),
  })
  if (!linkResponse.ok) return json({ error: "issue_failed" }, 500)
  const link = await linkResponse.json()
  const tokenHash = link.hashed_token ?? link.properties?.hashed_token
  if (typeof tokenHash !== "string" || !tokenHash) return json({ error: "issue_failed" }, 500)

  const verifyResponse = await fetch(`${supabaseUrl}/auth/v1/verify`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${anonKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ type: "magiclink", token_hash: tokenHash }),
  })
  if (!verifyResponse.ok) return json({ error: "issue_failed" }, 500)
  const verified = await verifyResponse.json()
  const accessToken = verified.access_token
  if (typeof accessToken !== "string" || !accessToken) return json({ error: "issue_failed" }, 500)

  const claims = payload(accessToken)
  const sessionId = claims?.session_id
  if (typeof sessionId !== "string" || !sessionId || sessionId === "00000000-0000-0000-0000-000000000000") {
    return json({ error: "issue_failed" }, 500)
  }

  const releaseResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/guest_release_session`, {
    method: "POST",
    headers: adminHeaders,
    body: JSON.stringify({ p_session_id: sessionId }),
  })
  if (!releaseResponse.ok) return json({ error: "issue_failed" }, 500)

  const expiresAt = typeof claims?.exp === "number" ? claims.exp : null
  return json({
    access_token: accessToken,
    token_type: "bearer",
    expires_at: expiresAt,
    user_id: SHOWCASE_USER_ID,
  })
})
