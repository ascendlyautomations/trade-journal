import { resolveStripeServerConfig } from "./stripeServerConfig.ts"

export type AffiliateConnectSyncFailureCategory =
  | "unauthenticated"
  | "stripe_not_configured"
  | "stripe_invalid_format"
  | "affiliate_missing"
  | "connected_account_missing"
  | "stripe_account_missing"
  | "stripe_auth_invalid"
  | "stripe_transient"
  | "stripe_deterministic"
  | "database_read"
  | "database_write"
  | "unexpected"

export type AffiliateConnectSyncLogFields = {
  requestId: string
  environment: string
  elapsedMs: number
  viewerPresent: boolean
  affiliatePresent: boolean
  connectedAccountPresent: boolean
  stripeConfigured: boolean
  stripeMode: "test" | "live" | "missing" | "invalid"
  category: AffiliateConnectSyncFailureCategory | "success" | "skipped"
  retryable: boolean
  status: number
}

export function newAffiliateConnectSyncRequestId(): string {
  return `acs_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`
}

export function stripeModeForLog(): AffiliateConnectSyncLogFields["stripeMode"] {
  const config = resolveStripeServerConfig()
  if (config.status === "missing") return "missing"
  if (config.status === "invalid_format") return "invalid"
  return config.mode
}

export function logAffiliateConnectSync(fields: AffiliateConnectSyncLogFields) {
  if (process.env.NODE_ENV === "production") {
    console.info("[connect/sync]", {
      requestId: fields.requestId,
      environment: fields.environment,
      elapsedMs: fields.elapsedMs,
      viewerPresent: fields.viewerPresent,
      affiliatePresent: fields.affiliatePresent,
      connectedAccountPresent: fields.connectedAccountPresent,
      stripeConfigured: fields.stripeConfigured,
      stripeMode: fields.stripeMode,
      category: fields.category,
      retryable: fields.retryable,
      status: fields.status,
    })
    return
  }

  console.info("[connect/sync]", fields)
}
