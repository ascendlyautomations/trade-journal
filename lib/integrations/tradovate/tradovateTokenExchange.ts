import { getTradovateOAuthConfig } from "./tradovateOAuthEnv"

export type TradovateOAuthTokenSuccess = {
  access_token: string
  refresh_token?: string | null
  token_type?: string | null
  expires_in?: number | null
  refresh_token_expires_in?: number | null
  id_token?: string | null
}

export type TradovateOAuthTokenFailure = {
  error: string
  error_description?: string | null
}

export type TradovateTokenExchangeResult =
  | { ok: true; tokens: TradovateOAuthTokenSuccess }
  | { ok: false; reason: "malformed" | "oauth_error" | "network"; oauthError?: string }

export async function exchangeTradovateAuthorizationCode(
  code: string
): Promise<TradovateTokenExchangeResult> {
  const config = getTradovateOAuthConfig()
  const trimmedCode = code.trim()
  if (!trimmedCode) {
    return { ok: false, reason: "malformed" }
  }

  const tokenRequestFields = {
    grant_type: "authorization_code",
    client_id: config.clientId,
    client_secret: config.clientSecret,
    redirect_uri: config.redirectUri,
    code: trimmedCode,
  }

  async function postTokenExchange(contentType: "json" | "form"): Promise<Response> {
    if (contentType === "json") {
      return fetch(config.tokenUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify(tokenRequestFields),
      })
    }
    return fetch(config.tokenUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
      },
      body: new URLSearchParams(tokenRequestFields),
    })
  }

  let response: Response
  try {
    response = await postTokenExchange("json")
    if (!response.ok && (response.status === 415 || response.status === 400)) {
      response = await postTokenExchange("form")
    }
  } catch {
    return { ok: false, reason: "network" }
  }

  let body: unknown
  try {
    body = await response.json()
  } catch {
    return { ok: false, reason: "malformed" }
  }

  if (!body || typeof body !== "object") {
    return { ok: false, reason: "malformed" }
  }

  const record = body as Record<string, unknown>
  const oauthError =
    typeof record.error === "string" && record.error.trim()
      ? record.error.trim()
      : null

  if (oauthError || !response.ok) {
    return {
      ok: false,
      reason: "oauth_error",
      oauthError: oauthError ?? "token_exchange_failed",
    }
  }

  const accessToken =
    typeof record.access_token === "string" ? record.access_token.trim() : ""
  if (!accessToken) {
    return { ok: false, reason: "malformed" }
  }

  return {
    ok: true,
    tokens: {
      access_token: accessToken,
      refresh_token:
        typeof record.refresh_token === "string" ? record.refresh_token : null,
      token_type: typeof record.token_type === "string" ? record.token_type : null,
      expires_in:
        typeof record.expires_in === "number" ? record.expires_in : null,
      refresh_token_expires_in:
        typeof record.refresh_token_expires_in === "number"
          ? record.refresh_token_expires_in
          : null,
      id_token: typeof record.id_token === "string" ? record.id_token : null,
    },
  }
}

export function parseTradovateIdTokenSubject(idToken: string | null | undefined): string | null {
  if (!idToken?.trim()) return null
  const parts = idToken.trim().split(".")
  if (parts.length < 2) return null
  try {
    const payload = JSON.parse(
      Buffer.from(parts[1]!, "base64url").toString("utf8")
    ) as Record<string, unknown>
    const sub = payload.sub
    return typeof sub === "string" && sub.trim() ? sub.trim() : null
  } catch {
    return null
  }
}

export type TradovateMeProfile = {
  userId?: number | string
  fullName?: string
}

export async function fetchTradovateMeProfile(
  accessToken: string
): Promise<TradovateMeProfile | null> {
  const config = getTradovateOAuthConfig()
  let response: Response
  try {
    response = await fetch(config.meUrl, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: "application/json",
      },
    })
  } catch {
    return null
  }
  if (!response.ok) return null
  try {
    const body = (await response.json()) as TradovateMeProfile
    return body && typeof body === "object" ? body : null
  } catch {
    return null
  }
}
