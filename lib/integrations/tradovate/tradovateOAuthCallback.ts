import { resolveAppUrl } from "@/lib/stripeServer"

export const TRADOVATE_OAUTH_CALLBACK_PATH =
  "/api/integrations/tradovate/callback" as const

/** Canonical redirect URI for Tradovate OAuth app registration. */
export const TRADOVATE_OAUTH_REDIRECT_URI =
  "https://www.tradetraxs.com/api/integrations/tradovate/callback" as const

export type TradovateCallbackOutcome =
  | { kind: "success" }
  | {
      kind: "error"
      reason:
        | "denied"
        | "invalid_state"
        | "missing_code"
        | "state_expired"
        | "token_exchange"
        | "identity_mismatch"
        | "server"
    }

type TradovateCallbackErrorReason = Extract<
  TradovateCallbackOutcome,
  { kind: "error" }
>["reason"]

const REASON_MESSAGES: Record<TradovateCallbackErrorReason, string> = {
    denied: "Tradovate authorization was cancelled or denied.",
    invalid_state: "This connection attempt expired or was invalid. Please try again from TradeTraxs.",
    missing_code: "Tradovate did not return an authorization code. Please try again.",
    state_expired: "This connection attempt expired. Please start again from TradeTraxs.",
    token_exchange:
      "Tradovate authorized the connection, but TradeTraxs could not finish linking. Please try again.",
    identity_mismatch:
      "You signed into a different Tradovate login than this connection. Reconnect with the original login or add a new connection instead.",
    server: "We could not complete the Tradovate connection. Please try again.",
  }

export function tradovateCallbackUserMessage(outcome: TradovateCallbackOutcome): string {
  if (outcome.kind === "success") {
    return "Tradovate is connected. Trade import and sync will arrive in a future update."
  }
  return REASON_MESSAGES[outcome.reason]
}

export function buildTradovateIntegrationResultUrl(
  req: Request,
  outcome: TradovateCallbackOutcome
): string {
  const base = resolveAppUrl(req)
  const url = new URL("/settings/integrations/tradovate", base)
  url.searchParams.set("status", outcome.kind === "success" ? "success" : "error")
  if (outcome.kind === "error") {
    url.searchParams.set("reason", outcome.reason)
  }
  return url.toString()
}

export type TradovateCallbackQuery = {
  code: string | null
  state: string | null
  oauthError: string | null
  oauthErrorDescription: string | null
}

export function parseTradovateCallbackQuery(
  searchParams: URLSearchParams
): TradovateCallbackQuery {
  return {
    code: searchParams.get("code")?.trim() || null,
    state: searchParams.get("state")?.trim() || null,
    oauthError: searchParams.get("error")?.trim() || null,
    oauthErrorDescription: searchParams.get("error_description")?.trim() || null,
  }
}

/**
 * Phase-2 hook: exchange `code` for tokens using server-side TRADOVATE_* secrets.
 * Intentionally not implemented until Tradovate token endpoint contract is finalized in-repo.
 */
export type TradovateAuthorizationCodePayload = {
  code: string
  userId: string
}
