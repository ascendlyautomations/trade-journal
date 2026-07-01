import type { SupabaseClient } from "@supabase/supabase-js"
import { normalizeProfileUsername } from "@/lib/profileUsername"

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

function formatReferralBody(username: string | null | undefined): string {
  const normalized = username ? normalizeProfileUsername(username) : ""
  if (normalized) {
    return `@${normalized} just signed up using your referral code.`
  }
  return "A new user just signed up using your referral code."
}

function formatCommissionBody(
  username: string | null | undefined,
  amount: number
): string {
  const amountStr = amount.toFixed(2)
  const normalized = username ? normalizeProfileUsername(username) : ""
  if (normalized) {
    return `@${normalized} became a paying TraxPro subscriber. You earned $${amountStr} in affiliate commission.`
  }
  return `A new user became a paying TraxPro subscriber. You earned $${amountStr} in affiliate commission.`
}

async function loadReferredUsername(
  admin: SupabaseClient,
  referredUserId: string
): Promise<string | null> {
  const { data } = await admin
    .from("profiles")
    .select("username")
    .eq("id", referredUserId)
    .maybeSingle()

  const username = data?.username != null ? String(data.username).trim() : ""
  return username || null
}

/** One notification per affiliate + referred user pair (deduped by unique index). */
export async function createAffiliateReferralNotification(
  admin: SupabaseClient,
  params: { affiliateUserId: string; referredUserId: string }
): Promise<void> {
  const { affiliateUserId, referredUserId } = params
  if (!affiliateUserId || !referredUserId || affiliateUserId === referredUserId) {
    return
  }

  const username = await loadReferredUsername(admin, referredUserId)
  const content: AffiliateNotificationContent = {
    title: "🎉 New Referral!",
    body: formatReferralBody(username),
    href: "/affiliate",
  }

  const { error } = await admin.from("notifications").insert({
    user_id: affiliateUserId,
    sender_id: referredUserId,
    type: "affiliate_referral",
    content: JSON.stringify(content),
    read: false,
  })

  if (error) {
    if (error.code === "23505") return
    console.error("[affiliate-notification] referral insert failed", {
      affiliateUserId,
      referredUserId,
      error,
    })
  }
}

/** One commission notification per affiliate + referred user pair (first paid invoice only). */
export async function createAffiliateCommissionNotification(
  admin: SupabaseClient,
  params: {
    affiliateUserId: string
    referredUserId: string
    commissionAmount: number
  }
): Promise<void> {
  const { affiliateUserId, referredUserId, commissionAmount } = params
  if (!affiliateUserId || !referredUserId || affiliateUserId === referredUserId) {
    return
  }
  if (!Number.isFinite(commissionAmount) || commissionAmount <= 0) {
    return
  }

  const username = await loadReferredUsername(admin, referredUserId)
  const content: AffiliateNotificationContent = {
    title: "💰 Commission Earned!",
    body: formatCommissionBody(username, commissionAmount),
    href: "/affiliate",
  }

  const { error } = await admin.from("notifications").insert({
    user_id: affiliateUserId,
    sender_id: referredUserId,
    type: "affiliate_commission_earned",
    content: JSON.stringify(content),
    read: false,
  })

  if (error) {
    if (error.code === "23505") return
    console.error("[affiliate-notification] commission insert failed", {
      affiliateUserId,
      referredUserId,
      commissionAmount,
      error,
    })
  }
}
