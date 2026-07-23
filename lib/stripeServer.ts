import Stripe from "stripe"
import { getRequestOrigin } from "@/lib/requestOrigin"

let stripeSingleton: Stripe | null = null
let stripeSingletonKey: string | null = null

/** True when the configured secret key is a Stripe Test Mode key. */
export function isStripeSecretKeyTestMode(
  key: string | null | undefined = process.env.STRIPE_SECRET_KEY
): boolean {
  return Boolean(key?.trim().startsWith("sk_test_"))
}

export function getStripeServer(): Stripe {
  const key = process.env.STRIPE_SECRET_KEY?.trim()
  if (!key) {
    throw new Error("Missing STRIPE_SECRET_KEY")
  }
  if (!stripeSingleton || stripeSingletonKey !== key) {
    if (key.startsWith("sk_test_")) {
      console.warn(
        "[stripeServer] STRIPE_SECRET_KEY is a Test Mode key (sk_test_). Live Stripe customers/subscriptions will not be found."
      )
    }
    stripeSingleton = new Stripe(key)
    stripeSingletonKey = key
  }
  return stripeSingleton
}

/** Public site URL for Stripe redirect URLs; prefer env in production (HTTPS). */
export function resolveAppUrl(req: Request): string {
  const env = process.env.NEXT_PUBLIC_BASE_URL?.trim()
  if (env) return env.replace(/\/$/, "")
  // Prefer Host / X-Forwarded-* — request.url is often localhost in Next.js
  // even when the client connected via a LAN IP.
  return getRequestOrigin(req).replace(/\/$/, "")
}
