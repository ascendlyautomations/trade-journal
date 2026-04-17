import type { SupabaseClient } from "@supabase/supabase-js"
import type Stripe from "stripe"
import { stripeAccountToAffiliateConnectPatch } from "@/lib/affiliateStripeConnect"
import { getStripeServer } from "@/lib/stripeServer"

export type EnsureStripeConnectAccountResult =
  | { ok: true; accountId: string; created: boolean }
  | { ok: false; error: string; status: number }

/**
 * Ensures `affiliates.stripe_connected_account_id` exists: reuses existing or creates Express + syncs flags.
 * Callers must use the service-role client (needs `auth.admin.getUserById`).
 */
export async function ensureStripeConnectAccountForUser(
  supabase: SupabaseClient,
  userId: string
): Promise<EnsureStripeConnectAccountResult> {
  const { data: affiliate, error: affErr } = await supabase
    .from("affiliates")
    .select("id, stripe_connected_account_id")
    .eq("user_id", userId)
    .maybeSingle()

  if (affErr || !affiliate?.id) {
    return { ok: false, error: "Affiliate row not found", status: 404 }
  }

  const existingId = affiliate.stripe_connected_account_id?.trim()
  if (existingId) {
    return { ok: true, accountId: existingId, created: false }
  }

  let stripe: Stripe
  try {
    stripe = getStripeServer()
  } catch {
    return { ok: false, error: "Stripe is not configured", status: 503 }
  }

  const { data: authData } = await supabase.auth.admin.getUserById(userId)
  const email = authData.user?.email ?? undefined

  const { data: profile } = await supabase
    .from("profiles")
    .select("name, username")
    .eq("id", userId)
    .maybeSingle()

  const raw = profile as { name?: string | null; username?: string | null } | null
  const displayName =
    String(raw?.name ?? "")
      .trim()
      .replace(/\s+/g, " ") ||
    String(raw?.username ?? "")
      .trim()
      .replace(/\s+/g, " ")

  const country = process.env.STRIPE_CONNECT_DEFAULT_COUNTRY?.trim() || "US"

  const createParams: Stripe.AccountCreateParams = {
    type: "express",
    country,
    email,
    capabilities: {
      transfers: { requested: true },
    },
    metadata: {
      trade_trax_user_id: userId,
      trade_trax_affiliate_row_id: String(affiliate.id),
    },
  }

  if (displayName) {
    createParams.business_profile = { name: displayName.slice(0, 255) }
  }

  const account = await stripe.accounts.create(createParams)

  const syncPatch: Record<string, unknown> = {
    stripe_connected_account_id: account.id,
    stripe_onboarding_updated_at: new Date().toISOString(),
  }

  try {
    const refreshed = await stripe.accounts.retrieve(account.id)
    Object.assign(syncPatch, stripeAccountToAffiliateConnectPatch(refreshed))
  } catch {
    // optional retrieve after create
  }

  const { error: updErr } = await supabase.from("affiliates").update(syncPatch).eq("id", affiliate.id)

  if (updErr) {
    console.error("[ensureStripeConnectAccountForUser] affiliates update:", updErr)
    return { ok: false, error: "Could not save connected account", status: 500 }
  }

  return { ok: true, accountId: account.id, created: true }
}
