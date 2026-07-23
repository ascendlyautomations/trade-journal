import { hapticSuccess } from "@/lib/nativeHaptics"

/** Client-side signals that Stripe checkout finished and membership must be reconciled. */

const STRIPE_RETURN_AT_KEY = "tradetraxs_stripe_return_at_v1"
const RECONCILE_PENDING_KEY = "tradetraxs_stripe_reconcile_pending_v1"
const DEFAULT_MAX_AGE_MS = 30 * 60 * 1000

export const STRIPE_RECONCILIATION_COMPLETE_EVENT =
  "tradetraxs:stripe-reconciliation-complete"

type ReconcilePending = {
  userId: string
  at: number
}

function readPending(): ReconcilePending | null {
  if (typeof window === "undefined") return null
  try {
    const raw = sessionStorage.getItem(RECONCILE_PENDING_KEY)
    if (!raw) return null
    const parsed = JSON.parse(raw) as ReconcilePending
    if (!parsed?.userId || typeof parsed.at !== "number") return null
    return parsed
  } catch {
    return null
  }
}

function isFresh(at: number, maxAgeMs: number): boolean {
  return Number.isFinite(at) && Date.now() - at <= maxAgeMs
}

/** Record that the browser returned from Stripe (success URL or checkout redirect). */
export function noteStripeCheckoutReturn() {
  if (typeof window === "undefined") return
  try {
    sessionStorage.setItem(STRIPE_RETURN_AT_KEY, String(Date.now()))
  } catch {
    /* ignore */
  }
}

/** Mark a user as awaiting membership reconciliation until trial/subscription is active. */
export function markStripeReconciliationPending(userId: string) {
  if (typeof window === "undefined") return
  const key = userId.trim()
  if (!key) return
  try {
    noteStripeCheckoutReturn()
    sessionStorage.setItem(
      RECONCILE_PENDING_KEY,
      JSON.stringify({ userId: key, at: Date.now() } satisfies ReconcilePending)
    )
  } catch {
    /* ignore */
  }
}

export function hasRecentStripeCheckoutReturn(
  maxAgeMs: number = DEFAULT_MAX_AGE_MS
): boolean {
  if (typeof window === "undefined") return false
  try {
    const raw = sessionStorage.getItem(STRIPE_RETURN_AT_KEY)
    if (!raw) return false
    const at = Number(raw)
    return isFresh(at, maxAgeMs)
  } catch {
    return false
  }
}

/** Whether membership sync should run for this user (survives URL param removal). */
export function shouldReconcileStripeMembership(
  userId: string,
  maxAgeMs: number = DEFAULT_MAX_AGE_MS
): boolean {
  const key = userId.trim()
  if (!key) return false

  const pending = readPending()
  if (pending?.userId === key && isFresh(pending.at, maxAgeMs)) {
    return true
  }

  return hasRecentStripeCheckoutReturn(maxAgeMs)
}

export function clearStripeReconciliationSignals() {
  if (typeof window === "undefined") return
  try {
    sessionStorage.removeItem(STRIPE_RETURN_AT_KEY)
    sessionStorage.removeItem(RECONCILE_PENDING_KEY)
  } catch {
    /* ignore */
  }
}

export function dispatchStripeReconciliationComplete() {
  if (typeof window === "undefined") return
  hapticSuccess("subscription-activated")
  window.dispatchEvent(new CustomEvent(STRIPE_RECONCILIATION_COMPLETE_EVENT))
}

export function subscribeStripeReconciliationComplete(
  listener: () => void
): () => void {
  if (typeof window === "undefined") return () => {}
  const handler = () => listener()
  window.addEventListener(STRIPE_RECONCILIATION_COMPLETE_EVENT, handler)
  return () =>
    window.removeEventListener(STRIPE_RECONCILIATION_COMPLETE_EVENT, handler)
}

/** Call once on client boot when the success URL is present. */
export function captureStripeCheckoutSuccessFromUrl() {
  if (typeof window === "undefined") return
  const params = new URLSearchParams(window.location.search)
  if (params.get("checkout") !== "success") return
  noteStripeCheckoutReturn()
}
