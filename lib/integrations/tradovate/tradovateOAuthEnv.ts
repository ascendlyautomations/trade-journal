import { TRADOVATE_OAUTH_REDIRECT_URI as DEFAULT_REDIRECT_URI } from "./tradovateOAuthCallback"

export type TradovateApiEnvironment = "demo" | "live"

/** Browser OAuth login — same host for demo and live apps per Tradovate's official example. */
const DEFAULT_AUTHORIZE_URL = "https://trader.tradovate.com/oauth"

const TOKEN_URL_BY_ENV: Record<TradovateApiEnvironment, string> = {
  demo: "https://demo.tradovateapi.com/v1/auth/oauthtoken",
  live: "https://live.tradovateapi.com/v1/auth/oauthtoken",
}

const ME_URL_BY_ENV: Record<TradovateApiEnvironment, string> = {
  demo: "https://demo.tradovateapi.com/v1/auth/me",
  live: "https://live.tradovateapi.com/v1/auth/me",
}

/** Official REST API base (Account List: GET /v1/account/list). */
export const TRADOVATE_REST_BASE_BY_ENV: Record<TradovateApiEnvironment, string> = {
  demo: "https://demo.tradovateapi.com",
  live: "https://live.tradovateapi.com",
}

/** Official user WebSocket (not market data): wss://{demo|live}.tradovateapi.com/v1/websocket */
export const TRADOVATE_WEBSOCKET_URL_BY_ENV: Record<TradovateApiEnvironment, string> = {
  demo: "wss://demo.tradovateapi.com/v1/websocket",
  live: "wss://live.tradovateapi.com/v1/websocket",
}

export function getTradovateWebSocketUrl(
  apiEnvironment: TradovateApiEnvironment
): string {
  const override = process.env.TRADOVATE_WEBSOCKET_URL?.trim()
  if (override) return override
  return TRADOVATE_WEBSOCKET_URL_BY_ENV[apiEnvironment]
}

export function getTradovateRestBaseUrl(apiEnvironment: TradovateApiEnvironment): string {
  const override = process.env.TRADOVATE_REST_BASE_URL?.trim()
  if (override) return override.replace(/\/$/, "")
  return TRADOVATE_REST_BASE_BY_ENV[apiEnvironment]
}

function readApiEnvironment(): TradovateApiEnvironment {
  const raw = process.env.TRADOVATE_API_ENV?.trim().toLowerCase()
  if (raw === "live") return "live"
  return "demo"
}

export function getTradovateOAuthConfig() {
  const clientId = process.env.TRADOVATE_CLIENT_ID?.trim()
  const clientSecret = process.env.TRADOVATE_CLIENT_SECRET?.trim()
  const redirectUri =
    process.env.TRADOVATE_OAUTH_REDIRECT_URI?.trim() || DEFAULT_REDIRECT_URI
  const apiEnvironment = readApiEnvironment()

  if (!clientId || !clientSecret) {
    throw new Error("tradovate_oauth_config_missing")
  }

  // Demo vs live affects REST token/me hosts only; authorization stays on trader.tradovate.com unless overridden.
  const authorizeUrl =
    process.env.TRADOVATE_OAUTH_AUTHORIZE_URL?.trim() || DEFAULT_AUTHORIZE_URL
  const tokenUrl =
    process.env.TRADOVATE_OAUTH_TOKEN_URL?.trim() ||
    TOKEN_URL_BY_ENV[apiEnvironment]
  const meUrl =
    process.env.TRADOVATE_OAUTH_ME_URL?.trim() || ME_URL_BY_ENV[apiEnvironment]

  return {
    clientId,
    clientSecret,
    redirectUri,
    authorizeUrl,
    tokenUrl,
    meUrl,
    apiEnvironment,
  }
}

export function buildTradovateAuthorizationUrl(params: {
  state: string
}): string {
  const config = getTradovateOAuthConfig()
  const url = new URL(config.authorizeUrl)
  url.searchParams.set("response_type", "code")
  url.searchParams.set("client_id", config.clientId)
  url.searchParams.set("redirect_uri", config.redirectUri)
  url.searchParams.set("state", params.state)
  return url.toString()
}
