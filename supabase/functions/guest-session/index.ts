import "jsr:@supabase/functions-js/edge-runtime.d.ts"

/** Default production showcase account — override with SHOWCASE_USER_ID secret/env. */
const DEFAULT_SHOWCASE_USER_ID = "3daf15b8-2f5d-48c8-ac98-75bca6c878f4"

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

function resolveShowcaseUserId(): string | null {
  const configured = Deno.env.get("SHOWCASE_USER_ID")?.trim()
  const candidate = configured && configured.length > 0 ? configured : DEFAULT_SHOWCASE_USER_ID
  return UUID_RE.test(candidate) ? candidate.toLowerCase() : null
}

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

  const showcaseUserId = resolveShowcaseUserId()
  if (!showcaseUserId) return json({ error: "showcase_misconfigured" }, 500)

  const supabaseUrl = Deno.env.get("SUPABASE_URL")
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")
  if (!supabaseUrl || !serviceKey || !anonKey) return json({ error: "unavailable" }, 500)

  const adminHeaders = {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
  }

  const userResponse = await fetch(`${supabaseUrl}/auth/v1/admin/users/${showcaseUserId}`, {
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
    user_id: showcaseUserId,
  })
})
