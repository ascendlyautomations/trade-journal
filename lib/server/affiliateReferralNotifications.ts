import type { SupabaseClient } from "@supabase/supabase-js"
import { notify } from "@/lib/server/notifications/NotificationService"

export type AffiliateNotificationContent = {
  title: string
  body: string
  href: string
}

export async function resolveAffiliateUserIdFromCode(
  admin: SupabaseClient,
  referralCode: string
): Promise<string | null> {
  const code = referralCode.trim().toUpperCase()
  if (!code) return null

  const { data: affiliateRow } = await admin
    .from("affiliates")
    .select("user_id")
    .eq("code", code)
    .maybeSingle()

  if (affiliateRow?.user_id) {
    return String(affiliateRow.user_id)
  }

  const { data: profileRow } = await admin
    .from("profiles")
    .select("id")
    .eq("referral_code", code)
    .maybeSingle()

  return profileRow?.id != null ? String(profileRow.id) : null
}

/** One notification per affiliate + referred user pair (deduped by unique index). */
export async function createAffiliateReferralNotification(
  _admin: SupabaseClient,
  params: { affiliateUserId: string; referredUserId: string }
): Promise<void> {
  await notify({
    type: "affiliate_referral",
    affiliateUserId: params.affiliateUserId,
    referredUserId: params.referredUserId,
  })
}

/** One commission notification per affiliate + referred user pair (first paid invoice only). */
export async function createAffiliateCommissionNotification(
  _admin: SupabaseClient,
  params: {
    affiliateUserId: string
    referredUserId: string
    commissionAmount: number
  }
): Promise<void> {
  await notify({
    type: "affiliate_commission_earned",
    affiliateUserId: params.affiliateUserId,
    referredUserId: params.referredUserId,
    commissionAmount: params.commissionAmount,
  })
}
