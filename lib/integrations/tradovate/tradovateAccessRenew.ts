import type { TradovateApiEnvironment } from "@/lib/integrations/tradovate/tradovateOAuthEnv"
import { getTradovateRestBaseUrl } from "@/lib/integrations/tradovate/tradovateOAuthEnv"

export type TradovateAccessRenewResult =
  | {
      ok: true
      accessToken: string
      expiresAt: Date | null
    }
  | { ok: false; reason: "network" | "http" | "malformed" }

/**
 * Tradovate session renew — extends the current access token without OAuth
 * refresh_token rotation. Official guidance for keeping a live session alive.
 * Must be called with a still-unexpired access token.
 */
export async function renewTradovateAccessToken(
  accessToken: string,
  apiEnvironment: TradovateApiEnvironment
): Promise<TradovateAccessRenewResult> {
  const trimmed = accessToken.trim()
  if (!trimmed) return { ok: false, reason: "malformed" }

  const base = getTradovateRestBaseUrl(apiEnvironment)
  let response: Response
  try {
    response = await fetch(`${base}/v1/auth/renewaccesstoken`, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${trimmed}`,
        Accept: "application/json",
      },
    })
  } catch {
    return { ok: false, reason: "network" }
  }

  if (!response.ok) return { ok: false, reason: "http" }

  let parsed: unknown
  try {
    parsed = await response.json()
  } catch {
    return { ok: false, reason: "malformed" }
  }
  if (!parsed || typeof parsed !== "object") {
    return { ok: false, reason: "malformed" }
  }

  const record = parsed as Record<string, unknown>
  const nextAccess =
    typeof record.accessToken === "string"
      ? record.accessToken.trim()
      : typeof record.access_token === "string"
        ? record.access_token.trim()
        : ""
  if (!nextAccess) return { ok: false, reason: "malformed" }

  const expirationRaw =
    typeof record.expirationTime === "string"
      ? record.expirationTime
      : typeof record.expiration_time === "string"
        ? record.expiration_time
        : null
  let expiresAt: Date | null = null
  if (expirationRaw) {
    const ms = new Date(expirationRaw).getTime()
    if (!Number.isNaN(ms)) expiresAt = new Date(ms)
  }

  return { ok: true, accessToken: nextAccess, expiresAt }
}
