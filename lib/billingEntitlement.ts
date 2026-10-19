/**
 * Client-side reading of GET /api/billing/entitlement.
 * The snapshot is the same contract native iOS already consumes.
 * Profile `is_pro` stays a Stripe/manual signal; it is not the only Pro check.
 */

export const ENTITLEMENT_UNAVAILABLE_MESSAGE =
  "Could not verify your plan. Try again."

export const ALREADY_PRO_CHECKOUT_MESSAGE =
  "You already have active Pro access. Stripe Checkout is not required."

export type TraxProEntitlementSource =
  | "none"
  | "stripe"
  | "apple"
  | "manual"
  | "creator"
  | "early_access"
  | "launch_access"

export type BillingEntitlementSnapshot = {
  traxProActive: boolean
  source: TraxProEntitlementSource
  plan: "pro" | "free"
  billingInterval: string | null
  subscriptionStatus: string | null
  trialEndsAt: string | null
  currentPeriodEndsAt: string | null
  cancelAtPeriodEnd: boolean
  appleExpiresAt: string | null
  appleProductId: string | null
  accessExpiresAt: string | null
  issuedAt: string
  appleSubscriptionStatus: string | null
  appleRevokedAt: string | null
}

export type BillingEntitlementStatus = "idle" | "loading" | "ready" | "error"

/** Confirmed Pro, confirmed Free, or not yet known. Unknown must not start checkout. */
export type ClientProAccess = "pro" | "free" | "unknown"

/**
 * How this account should manage billing.
 * `granted` is creator, manual, early access, or launch access with no live store subscription.
 * `unknown` means the snapshot does not identify a provider. Do not pick one.
 */
export type BillingProvider = "apple" | "stripe" | "granted" | "unknown"

export type StripeCheckoutDecision =
  | { action: "proceed" }
  | { action: "block_pro" }
  | { action: "unavailable" }

const SOURCES = new Set<TraxProEntitlementSource>([
  "none",
  "stripe",
  "apple",
  "manual",
  "creator",
  "early_access",
  "launch_access",
])

const STRIPE_LIVE_STATUSES = new Set(["active", "trialing"])
const APPLE_LIVE_STATUSES = new Set(["active", "grace_period", "billing_retry"])

function nullableString(value: unknown): string | null {
  if (typeof value !== "string") return null
  const trimmed = value.trim()
  return trimmed.length > 0 ? trimmed : null
}

export function parseBillingEntitlementResponse(
  body: unknown
): BillingEntitlementSnapshot | null {
  if (!body || typeof body !== "object") return null
  const row = body as Record<string, unknown>
  if (typeof row.traxProActive !== "boolean") return null
  if (row.plan !== "pro" && row.plan !== "free") return null
  const source = SOURCES.has(row.source as TraxProEntitlementSource)
    ? (row.source as TraxProEntitlementSource)
    : "none"
  return {
    traxProActive: row.traxProActive,
    source,
    plan: row.plan,
    billingInterval: nullableString(row.billingInterval),
    subscriptionStatus: nullableString(row.subscriptionStatus),
    trialEndsAt: nullableString(row.trialEndsAt),
    currentPeriodEndsAt: nullableString(row.currentPeriodEndsAt),
    cancelAtPeriodEnd: row.cancelAtPeriodEnd === true,
    appleExpiresAt: nullableString(row.appleExpiresAt),
    appleProductId: nullableString(row.appleProductId),
    accessExpiresAt: nullableString(row.accessExpiresAt),
    issuedAt: nullableString(row.issuedAt) ?? new Date(0).toISOString(),
    appleSubscriptionStatus: nullableString(row.appleSubscriptionStatus),
    appleRevokedAt: nullableString(row.appleRevokedAt),
  }
}

export function resolveClientProAccess(input: {
  signedIn: boolean
  profileIsPro: boolean
  status: BillingEntitlementStatus
  traxProActive: boolean | null
}): ClientProAccess {
  if (!input.signedIn) return input.profileIsPro ? "pro" : "free"
  if (input.status === "ready") return input.traxProActive ? "pro" : "free"
  if (input.profileIsPro) return "pro"
  return "unknown"
}

function stripeStatusLive(status: string | null): boolean {
  return STRIPE_LIVE_STATUSES.has((status ?? "").toLowerCase().trim())
}

/**
 * Stripe webhooks set `profiles.is_pro`, so the snapshot source is often `manual`
 * while `subscriptionStatus` is still the live Stripe status. That pair is Stripe.
 * A manual grant without a live Stripe status stays `granted`.
 */
export function resolveBillingProvider(
  snapshot: Pick<
    BillingEntitlementSnapshot,
    "traxProActive" | "source" | "subscriptionStatus"
  > | null
): BillingProvider {
  if (!snapshot?.traxProActive) return "unknown"
  if (snapshot.source === "apple") return "apple"
  if (snapshot.source === "stripe") return "stripe"
  if (snapshot.source === "manual" && stripeStatusLive(snapshot.subscriptionStatus)) {
    return "stripe"
  }
  if (
    snapshot.source === "manual" ||
    snapshot.source === "creator" ||
    snapshot.source === "early_access" ||
    snapshot.source === "launch_access"
  ) {
    return "granted"
  }
  return "unknown"
}

export function snapshotHasLiveAppleSubscription(
  snapshot: Pick<
    BillingEntitlementSnapshot,
    "appleSubscriptionStatus" | "appleRevokedAt"
  > | null
): boolean {
  if (!snapshot || snapshot.appleRevokedAt) return false
  return APPLE_LIVE_STATUSES.has(
    (snapshot.appleSubscriptionStatus ?? "").toLowerCase().trim()
  )
}

export function billingProviderLabel(provider: BillingProvider): string | null {
  switch (provider) {
    case "apple":
      return "App Store"
    case "stripe":
      return "Stripe"
    case "granted":
      return "Included with your account"
    case "unknown":
      return null
  }
}

/** `null` means the snapshot is not confirmed, so client preflights should not apply a Free cap. */
export function knownTraxProActiveForPreflight(
  access: ClientProAccess
): boolean | null {
  if (access === "pro") return true
  if (access === "free") return false
  return null
}

export function decideStripeCheckout(
  result: { ok: true; traxProActive: boolean } | { ok: false }
): StripeCheckoutDecision {
  if (!result.ok) return { action: "unavailable" }
  if (result.traxProActive) return { action: "block_pro" }
  return { action: "proceed" }
}

/** Block a new Stripe Checkout session until the snapshot is a confirmed Free result. */
export function clientCheckoutBlockReason(input: {
  signedIn: boolean
  status: BillingEntitlementStatus
  traxProActive: boolean | null
}): string | null {
  if (!input.signedIn) return null
  if (input.status === "idle" || input.status === "loading") {
    return "Checking your plan. Try again in a moment."
  }
  if (input.status === "error" || input.traxProActive == null) {
    return ENTITLEMENT_UNAVAILABLE_MESSAGE
  }
  if (input.traxProActive) return ALREADY_PRO_CHECKOUT_MESSAGE
  return null
}
