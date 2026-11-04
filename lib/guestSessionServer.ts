import { SHOWCASE_USER_ID } from "./guestShowcaseAccount"

export type MintedGuestSession = {
  userId: string
  accessToken: string
  refreshToken: string
  expiresAt: number | null
  sessionId: string
}

export function decodeJwtPayload(
  accessToken: string
): Record<string, unknown> | null {
  const parts = accessToken.split(".")
  if (parts.length < 2) return null
  const padded = parts[1].replace(/-/g, "+").replace(/_/g, "/")
  const pad = padded + "=".repeat((4 - (padded.length % 4)) % 4)
  try {
    return JSON.parse(Buffer.from(pad, "base64").toString("utf8")) as Record<
      string,
      unknown
    >
  } catch {
    return null
  }
}

function requireEnv(name: string): string | null {
  const value = process.env[name]?.trim()
  return value && value.length > 0 ? value : null
}

/** Mint showcase guest tokens without releasing the GoTrue session row (web install step). */
export async function mintShowcaseGuestSession(): Promise<MintedGuestSession | null> {
  const supabaseUrl = requireEnv("NEXT_PUBLIC_SUPABASE_URL")
  const serviceKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY")
  const anonKey = requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY")
  if (!supabaseUrl || !serviceKey || !anonKey) return null

  const base = supabaseUrl.replace(/\/+$/, "")
  const adminHeaders = {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
  }

  const userResponse = await fetch(
    `${base}/auth/v1/admin/users/${SHOWCASE_USER_ID}`,
    { headers: adminHeaders }
  )
  if (!userResponse.ok) return null
  const user = (await userResponse.json()) as { email?: string }
  const email = typeof user.email === "string" ? user.email : ""
  if (!email) return null

  const linkResponse = await fetch(`${base}/auth/v1/admin/generate_link`, {
    method: "POST",
    headers: adminHeaders,
    body: JSON.stringify({ type: "magiclink", email }),
  })
  if (!linkResponse.ok) return null
  const link = (await linkResponse.json()) as {
    hashed_token?: string
    properties?: { hashed_token?: string }
  }
  const tokenHash = link.hashed_token ?? link.properties?.hashed_token
  if (typeof tokenHash !== "string" || !tokenHash) return null

  const verifyResponse = await fetch(`${base}/auth/v1/verify`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${anonKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ type: "magiclink", token_hash: tokenHash }),
  })
  if (!verifyResponse.ok) return null

  const verified = (await verifyResponse.json()) as {
    access_token?: string
    refresh_token?: string
  }
  const accessToken = verified.access_token
  const refreshToken = verified.refresh_token
  if (typeof accessToken !== "string" || !accessToken) return null
  if (typeof refreshToken !== "string" || !refreshToken) return null

  const claims = decodeJwtPayload(accessToken)
  const sessionId = claims?.session_id
  if (typeof sessionId !== "string" || !sessionId) return null
  if (sessionId === "00000000-0000-0000-0000-000000000000") return null

  const sub = claims?.sub
  if (typeof sub !== "string" || sub.toLowerCase() !== SHOWCASE_USER_ID) {
    return null
  }

  const expiresAt =
    typeof claims?.exp === "number" && Number.isFinite(claims.exp)
      ? claims.exp
      : null

  return {
    userId: SHOWCASE_USER_ID,
    accessToken,
    refreshToken,
    expiresAt,
    sessionId,
  }
}

/** Drop the GoTrue session row so the JWT is read-only for Data API (matches guest-session edge). */
export async function releaseShowcaseGuestSession(
  sessionId: string
): Promise<boolean> {
  const supabaseUrl = requireEnv("NEXT_PUBLIC_SUPABASE_URL")
  const serviceKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY")
  if (!supabaseUrl || !serviceKey) return false

  const base = supabaseUrl.replace(/\/+$/, "")
  const response = await fetch(`${base}/rest/v1/rpc/guest_release_session`, {
    method: "POST",
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ p_session_id: sessionId }),
  })
  return response.ok
}
