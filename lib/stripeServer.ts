import Stripe from "stripe"

let stripeSingleton: Stripe | null = null

export function getStripeServer(): Stripe {
  if (!process.env.STRIPE_SECRET_KEY) {
    throw new Error("Missing STRIPE_SECRET_KEY")
  }
  if (!stripeSingleton) {
    stripeSingleton = new Stripe(process.env.STRIPE_SECRET_KEY)
  }
  return stripeSingleton
}

/** Public site URL for Stripe redirect URLs; prefer env in production (HTTPS). */
export function resolveAppUrl(req: Request): string {
  const env = process.env.NEXT_PUBLIC_BASE_URL?.trim()
  if (env) return env.replace(/\/$/, "")
  try {
    return new URL(req.url).origin
  } catch {
    return "http://localhost:3000"
  }
}
