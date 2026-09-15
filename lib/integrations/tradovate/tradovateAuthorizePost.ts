/** Must match ``TRADOVATE_NATIVE_OAUTH_RETURN_URL`` in ``tradovateOAuthCallback.ts``. */
export const TRADOVATE_NATIVE_OAUTH_REDIRECT_AFTER =
  "tradetraxs://settings/broker-integrations/tradovate" as const

/** POST body for `/api/integrations/tradovate/authorize`. */
export type TradovateAuthorizePostBody = {
  reconnectConnectionId?: string
  client?: string
}

export const TRADOVATE_NATIVE_OAUTH_CLIENT = "native" as const

/** Optional header mirror when JSON body is unavailable (same contract as `client: "native"`). */
export const TRADOVATE_NATIVE_OAUTH_CLIENT_HEADER =
  "x-tradetraxs-broker-oauth-client" as const

/** Native iOS JSON contract — must include Tradovate browser URL (state embedded in query). */
export type TradovateNativeAuthorizeJsonResponse = {
  ok: true
  authorizeUrl: string
}

/** Web SPA first step — cookie handoff; browser navigates GET /authorize next. */
export type TradovateWebAuthorizeJsonResponse = {
  ok: true
}

export function parseTradovateAuthorizePostBody(raw: unknown): TradovateAuthorizePostBody {
  if (!raw || typeof raw !== "object") {
    return {}
  }
  const record = raw as Record<string, unknown>
  const reconnectConnectionId =
    typeof record.reconnectConnectionId === "string"
      ? record.reconnectConnectionId
      : undefined
  const client = typeof record.client === "string" ? record.client : undefined
  return { reconnectConnectionId, client }
}

export function isNativeTradovateAuthorizeRequest(
  body: TradovateAuthorizePostBody,
  headerValue: string | null | undefined
): boolean {
  if (body.client?.trim().toLowerCase() === TRADOVATE_NATIVE_OAUTH_CLIENT) {
    return true
  }
  return headerValue?.trim().toLowerCase() === TRADOVATE_NATIVE_OAUTH_CLIENT
}

export function buildNativeTradovateAuthorizeJsonResponse(
  authorizeUrl: string
): TradovateNativeAuthorizeJsonResponse {
  const trimmed = authorizeUrl.trim()
  if (!trimmed) {
    throw new Error("tradovate_native_authorize_url_missing")
  }
  return { ok: true, authorizeUrl: trimmed }
}

export function buildWebTradovateAuthorizeJsonResponse(): TradovateWebAuthorizeJsonResponse {
  return { ok: true }
}

export function isValidHttpsAuthorizeUrl(url: string): boolean {
  try {
    const parsed = new URL(url)
    return parsed.protocol === "https:" && parsed.hostname.length > 0
  } catch {
    return false
  }
}
