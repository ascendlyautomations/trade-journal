import type { SupabaseClient } from "@supabase/supabase-js"
import {
  normalizeAffiliateCode,
  type AffiliateCheckoutRow,
} from "@/lib/affiliateStripeDiscount"

/**
 * Resolve affiliate for checkout from existing referred_by or a referral code body param.
 * Does not overwrite an existing referred_by with a different affiliate.
 */
export async function resolveAffiliateForCheckout(
  supabase: SupabaseClient,
  input: {
    buyerUserId: string
    existingReferredBy?: string | null
    referralCodeFromBody?: string | null
  }
): Promise<AffiliateCheckoutRow | null> {
  const preferred = normalizeAffiliateCode(
    input.existingReferredBy || input.referralCodeFromBody
  )
  if (!preferred) return null

  const { data, error } = await supabase
    .from("affiliates")
    .select("user_id, code, stripe_promo_code_id")
    .ilike("code", preferred)
    .maybeSingle()

  if (error || !data?.user_id || !data?.code) return null
  if (data.user_id === input.buyerUserId) return null

  return {
    user_id: String(data.user_id),
    code: normalizeAffiliateCode(data.code),
    stripe_promo_code_id:
      data.stripe_promo_code_id != null
        ? String(data.stripe_promo_code_id).trim() || null
        : null,
  }
}

/**
 * Persist durable DB attribution when the buyer is not yet attributed.
 * Returns whether referred_by was newly set.
 */
export async function ensureBuyerReferredBy(
  supabase: SupabaseClient,
  input: {
    buyerUserId: string
    affiliateCode: string
    existingReferredBy?: string | null
  }
): Promise<{ attributed: boolean; newlySet: boolean }> {
  const existing = normalizeAffiliateCode(input.existingReferredBy)
  const next = normalizeAffiliateCode(input.affiliateCode)
  if (!next) return { attributed: false, newlySet: false }
  if (existing) {
    return { attributed: true, newlySet: false }
  }

  const { error } = await supabase
    .from("profiles")
    .update({ referred_by: next })
    .eq("id", input.buyerUserId)

  if (error) throw error
  return { attributed: true, newlySet: true }
}
