import { supabase } from "./supabaseClient"
import { markStripeReconciliationPending } from "./stripeReconciliation"
import type { TraxProBillingIntervalId } from "./traxProBillingPlans"
import { TRAXPRO_DEFAULT_BILLING_INTERVAL } from "./traxProBillingPlans"

export type StartTraxProCheckoutOptions = {
  billingInterval?: TraxProBillingIntervalId
  referralCode?: string | null
}

export async function startTraxProCheckout(
  options: StartTraxProCheckoutOptions = {}
): Promise<string> {
  const {
    data: { session },
  } = await supabase.auth.getSession()
  const accessToken = session?.access_token

  if (!accessToken) {
    throw new Error("Not authenticated")
  }

  const billingInterval =
    options.billingInterval ?? TRAXPRO_DEFAULT_BILLING_INTERVAL

  const res = await fetch("/api/create-checkout-session", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      billingInterval,
      referralCode:
        options.referralCode ??
        (typeof window !== "undefined"
          ? localStorage.getItem("referral_code")
          : null),
    }),
  })

  const data = (await res.json()) as { url?: string; error?: string }

  if (!res.ok) {
    throw new Error(data?.error || "Checkout failed")
  }

  if (!data.url) {
    throw new Error("Missing checkout URL")
  }

  const userId = session?.user?.id
  if (userId) {
    markStripeReconciliationPending(userId)
  }

  return data.url
}
