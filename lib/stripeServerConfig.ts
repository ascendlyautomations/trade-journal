export type StripeServerConfigState =
  | { status: "configured"; mode: "test" | "live" }
  | { status: "missing" }
  | { status: "invalid_format" }

/** Presence/format check only — never returns secret values. */
export function resolveStripeServerConfig(): StripeServerConfigState {
  const key = process.env.STRIPE_SECRET_KEY?.trim()
  if (!key) return { status: "missing" }
  if (key.startsWith("sk_test_")) return { status: "configured", mode: "test" }
  if (key.startsWith("sk_live_")) return { status: "configured", mode: "live" }
  return { status: "invalid_format" }
}

export function isStripeServerConfigured(): boolean {
  return resolveStripeServerConfig().status === "configured"
}
