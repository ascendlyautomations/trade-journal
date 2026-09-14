import type { IntegrationCredentialPayload } from "@/lib/integrations/credentialEncryption"
import { getTradovateOAuthConfig } from "./tradovateOAuthEnv"
import type { TradovateOAuthTokenSuccess } from "./tradovateTokenExchange"

export type TradovateRefreshResult =
  | { ok: true; tokens: TradovateOAuthTokenSuccess }
  | { ok: false; reason: "no_refresh_token" | "oauth_error" | "network" | "malformed" }

export async function refreshTradovateAccessToken(
  refreshToken: string
): Promise<TradovateRefreshResult> {
  const config = getTradovateOAuthConfig()
  const trimmed = refreshToken.trim()
  if (!trimmed) return { ok: false, reason: "no_refresh_token" }

  const body = {
    grant_type: "refresh_token",
    client_id: config.clientId,
    client_secret: config.clientSecret,
    refresh_token: trimmed,
  }

  let response: Response
  try {
    response = await fetch(config.tokenUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify(body),
    })
  } catch {
    return { ok: false, reason: "network" }
  }

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
  const oauthError =
    typeof record.error === "string" && record.error.trim() ? record.error.trim() : null
  if (oauthError || !response.ok) {
    return { ok: false, reason: "oauth_error" }
  }

  const accessToken =
    typeof record.access_token === "string" ? record.access_token.trim() : ""
  if (!accessToken) return { ok: false, reason: "malformed" }

  return {
    ok: true,
    tokens: {
      access_token: accessToken,
      refresh_token:
        typeof record.refresh_token === "string" ? record.refresh_token : trimmed,
      token_type: typeof record.token_type === "string" ? record.token_type : null,
      expires_in:
        typeof record.expires_in === "number" ? record.expires_in : null,
      refresh_token_expires_in:
        typeof record.refresh_token_expires_in === "number"
          ? record.refresh_token_expires_in
          : null,
    },
  }
}

export function credentialsFromRefreshTokens(
  tokens: TradovateOAuthTokenSuccess
): IntegrationCredentialPayload {
  return {
    access_token: tokens.access_token,
    refresh_token: tokens.refresh_token ?? null,
    token_type: tokens.token_type ?? null,
  }
}

export function tokenExpiryDates(tokens: TradovateOAuthTokenSuccess): {
  accessTokenExpiresAt: Date | null
  refreshTokenExpiresAt: Date | null
} {
  const nowMs = Date.now()
  return {
    accessTokenExpiresAt:
      typeof tokens.expires_in === "number" && tokens.expires_in > 0
        ? new Date(nowMs + tokens.expires_in * 1000)
        : null,
    refreshTokenExpiresAt:
      typeof tokens.refresh_token_expires_in === "number" &&
      tokens.refresh_token_expires_in > 0
        ? new Date(nowMs + tokens.refresh_token_expires_in * 1000)
        : null,
  }
}
