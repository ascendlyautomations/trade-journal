import { createHmac, timingSafeEqual } from "crypto"
import type { IntegrationOAuthIntent } from "@/lib/integrations/integrationOAuthState"

/** Short-lived signed cookie so GET /authorize can run as top-level navigation (no Bearer header). */
export const TRADOVATE_AUTHORIZE_HANDOFF_COOKIE = "tt_tradovate_auth_handoff"

const HANDOFF_TTL_SECONDS = 120

export type TradovateAuthorizeHandoffPayload = {
  userId: string
  oauthIntent: IntegrationOAuthIntent
  targetConnectionId: string | null
}

function handoffSecret(): Buffer {
  const raw = process.env.INTEGRATION_CREDENTIALS_ENCRYPTION_KEY?.trim()
  if (!raw) {
    throw new Error("integration_credentials_encryption_key_missing")
  }
  const key = Buffer.from(raw, "base64url")
  if (key.length !== 32) {
    throw new Error("integration_credentials_encryption_key_invalid")
  }
  return key
}

export function createTradovateAuthorizeHandoffValue(
  params: TradovateAuthorizeHandoffPayload
): string {
  const exp = Math.floor(Date.now() / 1000) + HANDOFF_TTL_SECONDS
  const payloadB64 = Buffer.from(
    JSON.stringify({
      uid: params.userId,
      exp,
      intent: params.oauthIntent,
      cid: params.targetConnectionId,
    }),
    "utf8"
  ).toString("base64url")
  const sig = createHmac("sha256", handoffSecret()).update(payloadB64).digest("base64url")
  return `${payloadB64}.${sig}`
}

export function verifyTradovateAuthorizeHandoffValue(
  value: string
): TradovateAuthorizeHandoffPayload | null {
  const trimmed = value.trim()
  const dot = trimmed.lastIndexOf(".")
  if (dot <= 0) return null
  const payloadB64 = trimmed.slice(0, dot)
  const sig = trimmed.slice(dot + 1)
  if (!payloadB64 || !sig) return null

  const expected = createHmac("sha256", handoffSecret())
    .update(payloadB64)
    .digest("base64url")

  const sigBuf = Buffer.from(sig, "utf8")
  const expectedBuf = Buffer.from(expected, "utf8")
  if (sigBuf.length !== expectedBuf.length || !timingSafeEqual(sigBuf, expectedBuf)) {
    return null
  }

  try {
    const payload = JSON.parse(
      Buffer.from(payloadB64, "base64url").toString("utf8")
    ) as {
      uid?: string
      exp?: number
      intent?: string
      cid?: string | null
    }
    if (!payload.uid || typeof payload.uid !== "string") return null
    if (typeof payload.exp !== "number" || payload.exp < Math.floor(Date.now() / 1000)) {
      return null
    }
    const oauthIntent = payload.intent === "reconnect" ? "reconnect" : "connect_new"
    const targetConnectionId =
      oauthIntent === "reconnect" && typeof payload.cid === "string" && payload.cid.trim()
        ? payload.cid.trim()
        : null
    return {
      userId: payload.uid,
      oauthIntent,
      targetConnectionId,
    }
  } catch {
    return null
  }
}

export function tradovateAuthorizeHandoffCookieOptions(): {
  httpOnly: true
  secure: boolean
  sameSite: "lax"
  path: string
  maxAge: number
} {
  return {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/api/integrations/tradovate/authorize",
    maxAge: HANDOFF_TTL_SECONDS,
  }
}
