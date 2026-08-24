

import Stripe from "stripe"
import { createClient, type SupabaseClient } from "@supabase/supabase-js"
import {
  COMMISSION_RATE,
  calculateAffiliateCommission,
  centsToMajorUnits,
  extractStripePriceIdFromInvoice,
  resolveAffiliateCommissionBaseCents,
} from "@/lib/affiliateEarnings"
import {
  normalizeAffiliateCode,
  readAffiliateCodeFromStripeMetadata,
  resolveAffiliateCodeForCommission,
  shouldRecordAffiliateCommission,
} from "@/lib/affiliateStripeDiscount"
import {
  createAffiliateCommissionNotification,
  createAffiliateReferralNotification,
} from "@/lib/server/affiliateReferralNotifications"
import { resolveTraxProBillingIntervalFromStripePriceId } from "@/lib/traxProBillingPlans.server"
import { mirrorBillingAccountsStripeCustomerId } from "@/lib/profileSplitMirrorWrites"
import { enableAllAccountsForTradeEntry } from "@/lib/enableAllAccountsForTradeEntry"
import { devLog } from "@/lib/devLog"
import type { Database } from "@/lib/database.types"

export const runtime = "nodejs"

type ProfileUpdate = Database["public"]["Tables"]["profiles"]["Update"]

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY as string)

const supabase = createClient<Database>(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

/** Stripe subscription is active — mirror is_pro for legacy UI. */
const SUBSCRIPTION_ACTIVE = {
  subscription_status: "active" as const,
  is_pro: true as const,
}

const SUBSCRIPTION_INACTIVE = {
  subscription_status: "inactive" as const,
  is_pro: false as const,
}

function stripeCustomerId(
  customer: string | Stripe.Customer | Stripe.DeletedCustomer | null | undefined
): string | null {
  if (!customer) return null
  if (typeof customer === "string") return customer
  return "deleted" in customer && customer.deleted ? null : customer.id
}

function buildSubscriptionProfileUpdatePayload(
  subscription: Stripe.Subscription
): Record<string, unknown> {
  const status = subscription.status
  const updatePayload: Record<string, unknown> = {
    subscription_status: status,
    cancel_at_period_end: subscription.cancel_at_period_end ?? false,
    cancel_at:
      subscription.cancel_at != null
        ? new Date(subscription.cancel_at * 1000)
        : null,
    is_pro: status === "active" || status === "trialing",
  }

  if (subscription.trial_end) {
    updatePayload.trial_end = new Date(subscription.trial_end * 1000)
  }

  const itemPeriodEnd = subscription.items?.data?.[0]?.current_period_end
  const legacyPeriodEnd = (
    subscription as Stripe.Subscription & { current_period_end?: number | null }
  ).current_period_end
  const periodEnd = itemPeriodEnd ?? legacyPeriodEnd ?? null

  if (periodEnd) {
    updatePayload.current_period_end = new Date(periodEnd * 1000)
  } else if (subscription.trial_end && subscription.status !== "active") {
    updatePayload.current_period_end = new Date(subscription.trial_end * 1000)
  }

  const priceId = subscription.items?.data?.[0]?.price?.id ?? null
  if (priceId) {
    updatePayload.stripe_price_id = priceId
    const billingInterval = resolveTraxProBillingIntervalFromStripePriceId(priceId)
    if (billingInterval) {
      updatePayload.billing_interval = billingInterval
    }
  }

  const metadataInterval = subscription.metadata?.billing_interval
  if (
    typeof metadataInterval === "string" &&
    metadataInterval.trim() &&
    !updatePayload.billing_interval
  ) {
    updatePayload.billing_interval = metadataInterval.trim()
  }

  return updatePayload
}

async function syncSubscriptionToProfile(params: {
  supabase: SupabaseClient<Database>
  subscription: Stripe.Subscription
  logContext: string
}): Promise<boolean> {
  const { supabase, subscription, logContext } = params
  const customerId = stripeCustomerId(subscription.customer)

  if (!customerId) {
    devLog(`❌ subscription sync (${logContext}): missing customer id`)
    return false
  }

  const { data: profile, error: findErr } = await supabase
    .from("profiles")
    .select("id")
    .eq("stripe_customer_id", customerId)
    .maybeSingle()

  if (findErr) {
    console.error(`❌ subscription sync (${logContext}): profile lookup error:`, findErr, {
      customerId,
    })
    return false
  }

  if (!profile?.id) {
    console.error(
      `❌ No profile found for stripe_customer_id (${logContext}):`,
      customerId
    )
    return false
  }

  const updatePayload = buildSubscriptionProfileUpdatePayload(subscription)

  devLog(`[subscription sync] (${logContext}) applying update:`, {
    customerId,
    profileId: profile.id,
    status: subscription.status,
    cancel_at_period_end: subscription.cancel_at_period_end,
    cancel_at: subscription.cancel_at ?? null,
    updatePayload,
  })

  const { data: updatedRows, error: upErr } = await supabase
    .from("profiles")
    .update(updatePayload as ProfileUpdate)
    .eq("id", profile.id)
    .select("id")

  if (upErr) {
    console.error(`❌ Failed to update subscription (${logContext}):`, upErr, {
      customerId,
      profileId: profile.id,
    })
    return false
  }

  if (!updatedRows?.length) {
    console.error(`❌ subscription sync (${logContext}): 0 rows updated`, {
      customerId,
      profileId: profile.id,
    })
    return false
  }

  devLog(`✅ Subscription synced successfully (${logContext})`, {
    customerId,
    profileId: profile.id,
    rowsUpdated: updatedRows.length,
  })

  if (updatePayload.is_pro === true) {
    await enableAllAccountsForTradeEntry(supabase, profile.id)
  }

  return true
}

/**
 * Persist durable affiliate attribution from Checkout Session metadata and/or
 * promotion codes. Metadata is the durable source; promo codes remain a backup
 * path for manually entered codes.
 */
async function trackAffiliateAttributionFromCheckout(params: {
  stripe: Stripe
  supabase: SupabaseClient<Database>
  session: Stripe.Checkout.Session
  buyerProfileId: string
}): Promise<void> {
  const { stripe, supabase, session, buyerProfileId } = params

  const metaCode = readAffiliateCodeFromStripeMetadata(session.metadata)
  if (metaCode) {
    await applyAffiliateAttributionToBuyer({
      supabase,
      buyerProfileId,
      affiliateCode: metaCode,
      source: "session_metadata",
    })
    return
  }

  await trackAffiliateFromManualCheckoutDiscount({
    stripe,
    supabase,
    sessionId: session.id,
    buyerProfileId,
  })
}

async function applyAffiliateAttributionToBuyer(params: {
  supabase: SupabaseClient<Database>
  buyerProfileId: string
  affiliateCode: string
  source: string
}): Promise<void> {
  const { supabase, buyerProfileId, source } = params
  const affiliateCode = normalizeAffiliateCode(params.affiliateCode)
  if (!affiliateCode) return

  const { data: affiliate } = await supabase
    .from("affiliates")
    .select("id, user_id, code")
    .ilike("code", affiliateCode)
    .maybeSingle()

  if (!affiliate?.user_id || !affiliate.code) {
    devLog("⚠️ No affiliate row for attribution code:", affiliateCode, source)
    return
  }

  if (affiliate.user_id === buyerProfileId) {
    devLog("⚠️ Skip self-referral (buyer is affiliate owner)")
    return
  }

  const { data: buyer } = await supabase
    .from("profiles")
    .select("id, referred_by")
    .eq("id", buyerProfileId)
    .maybeSingle()

  const existing = normalizeAffiliateCode(buyer?.referred_by)
  if (existing) {
    devLog("ℹ️ Buyer already attributed:", existing, `(${source})`)
    return
  }

  const code = normalizeAffiliateCode(affiliate.code)
  const { error: buyerRefErr } = await supabase
    .from("profiles")
    .update({ referred_by: code })
    .eq("id", buyerProfileId)

  if (buyerRefErr) {
    console.error("ERROR:", JSON.stringify(buyerRefErr, null, 2))
    return
  }

  devLog("✅ Buyer referred_by set from", source, ":", code)
  try {
    await createAffiliateReferralNotification(supabase, {
      affiliateUserId: affiliate.user_id,
      referredUserId: buyerProfileId,
    })
  } catch (notifErr) {
    console.error("[checkout] affiliate referral notification failed:", notifErr)
  }

  const { data: referrerProfile, error: refFetchErr } = await supabase
    .from("profiles")
    .select("id, referral_count")
    .eq("id", affiliate.user_id)
    .maybeSingle()

  if (refFetchErr || !referrerProfile?.id) {
    devLog("❌ Referrer profile missing for affiliate.user_id:", affiliate.user_id)
    return
  }

  const { error: refUpErr } = await supabase
    .from("profiles")
    .update({
      referral_count: Number(referrerProfile.referral_count || 0) + 1,
    })
    .eq("id", referrerProfile.id)

  if (refUpErr) {
    console.error("ERROR:", JSON.stringify(refUpErr, null, 2))
  } else {
    devLog("✅ referral_count incremented for:", code)
  }
}

/**
 * When the customer enters a promotion code in Checkout, attribute affiliate
 * (referred_by + referral_count) — backup path when session metadata is absent.
 */
async function trackAffiliateFromManualCheckoutDiscount(params: {
  stripe: Stripe
  supabase: SupabaseClient<Database>
  sessionId: string
  buyerProfileId: string
}): Promise<void> {
  const { stripe, supabase, sessionId, buyerProfileId } = params

  devLog(
    "🎟️ checkout: resolving manual promotion codes for session",
    sessionId
  )

  let sessionWithDiscounts: Stripe.Checkout.Session
  try {
    sessionWithDiscounts = await stripe.checkout.sessions.retrieve(sessionId, {
      expand: ["total_details.breakdown.discounts", "discounts"],
    })
  } catch (e) {
    devLog("⚠️ checkout sessions.retrieve (discounts) failed:", e)
    return
  }

  const promoIds = new Set<string>()

  const discountsFromBreakdown = (
    sessionWithDiscounts as unknown as {
      total_details?: { breakdown?: { discounts?: unknown } }
    }
  ).total_details?.breakdown?.discounts

  if (Array.isArray(discountsFromBreakdown)) {
    for (const row of discountsFromBreakdown) {
      const d = row as Record<string, unknown>
      if (typeof d.promotion_code === "string") {
        promoIds.add(d.promotion_code)
      }
      const inner = d.discount
      if (inner && typeof inner === "object" && inner !== null) {
        const pc = (inner as { promotion_code?: string }).promotion_code
        if (typeof pc === "string") promoIds.add(pc)
      }
    }
  }

  const topDiscounts = (
    sessionWithDiscounts as unknown as { discounts?: unknown }
  ).discounts

  if (Array.isArray(topDiscounts)) {
    for (const row of topDiscounts) {
      const d = row as Record<string, unknown>
      if (typeof d.promotion_code === "string") {
        promoIds.add(d.promotion_code)
      }
    }
  }

  // Auto-applied discounts may also appear on session.total_details only; also
  // read durable metadata written at session create.
  const metaCode = readAffiliateCodeFromStripeMetadata(
    sessionWithDiscounts.metadata
  )
  if (metaCode) {
    await applyAffiliateAttributionToBuyer({
      supabase,
      buyerProfileId,
      affiliateCode: metaCode,
      source: "session_metadata_retrieve",
    })
    return
  }

  if (promoIds.size === 0) {
    devLog(
      "ℹ️ No promotion code discount on checkout — skip affiliate attribution"
    )
    return
  }

  devLog("🎟️ Promotion code ids from checkout:", [...promoIds])

  for (const promoId of promoIds) {
    type AffiliateRow = {
      id: string
      user_id: string
      code: string
      stripe_promo_code_id?: string | null
    }

    let affiliate: AffiliateRow | null = null

    const { data: byPromo } = await supabase
      .from("affiliates")
      .select("id, user_id, code, stripe_promo_code_id")
      .eq("stripe_promo_code_id", promoId)
      .maybeSingle()

    if (byPromo) {
      affiliate = byPromo as AffiliateRow
    } else {
      try {
        const promoObj = await stripe.promotionCodes.retrieve(promoId)
        const customerFacingCode = promoObj.code
        if (customerFacingCode) {
          const { data: byCode } = await supabase
            .from("affiliates")
            .select("id, user_id, code, stripe_promo_code_id")
            .eq("code", customerFacingCode)
            .maybeSingle()
          if (byCode) affiliate = byCode as AffiliateRow
        }
      } catch (e) {
        devLog("⚠️ promotionCodes.retrieve failed:", promoId, e)
      }
    }

    if (!affiliate) {
      devLog("⚠️ No affiliate row for promotion id:", promoId)
      continue
    }

    await applyAffiliateAttributionToBuyer({
      supabase,
      buyerProfileId,
      affiliateCode: affiliate.code,
      source: "manual_promo",
    })
    break
  }
}

export async function POST(req: Request) {
  devLog("🔥 WEBHOOK HIT")
  try {
    const body = await req.text()
    const sig = req.headers.get("stripe-signature")

    if (!sig) {
      console.error(
        "ERROR:",
        JSON.stringify({ message: "Missing stripe-signature header" }, null, 2)
      )
      return new Response("No signature", { status: 400 })
    }

    let event: Stripe.Event

    try {
      devLog(
        "🔐 Webhook secret exists:",
        !!process.env.STRIPE_WEBHOOK_SECRET
      )
      event = stripe.webhooks.constructEvent(
        body,
        sig,
        process.env.STRIPE_WEBHOOK_SECRET as string
      )
    } catch (err) {
      console.error(
        "ERROR:",
        JSON.stringify(
          err instanceof Error
            ? { message: err.message, name: err.name }
            : err,
          null,
          2
        )
      )
      return new Response("Invalid signature", { status: 400 })
    }

    devLog("📩 Event received:", event.type)
    devLog("📩 Stripe event:", event.type)

    switch (event.type) {
      case "checkout.session.completed":
      case "invoice.payment_succeeded":
      case "customer.subscription.created":
        devLog("➡️ Handling event:", event.type)
        break
      default:
        break
    }

    // ======================================================
    // ✅ CHECKOUT SESSION COMPLETED → link customer + Pro
    // ======================================================
    if (event.type === "checkout.session.completed") {
      devLog("📦 Processing checkout.session.completed")

      try {
        const session = event.data.object as Stripe.Checkout.Session
        const customerId = stripeCustomerId(session.customer)

        devLog("🔥 CHECKOUT COMPLETE — customerId:", customerId)

        let userId: string | null =
          session.metadata?.user_id ||
          session.metadata?.userId ||
          null
        devLog("👤 User ID from metadata:", userId)

        if (!userId && customerId) {
          const { data: byCustomer, error: lookupErr } = await supabase
            .from("profiles")
            .select("id")
            .eq("stripe_customer_id", customerId)
            .maybeSingle()

          if (lookupErr) {
            devLog("⚠️ checkout profile lookup by customer error:", lookupErr)
          }
          if (byCustomer?.id) {
            userId = byCustomer.id
            devLog("👤 Profile resolved via stripe_customer_id:", userId)
          }
        }

        if (!userId) {
          devLog(
            "❌ checkout.session.completed: could not resolve user (no metadata user id, no stripe_customer_id match)"
          )
        } else {
          devLog("🔥 Activating subscription for:", userId)

          try {
            let subscriptionPayload: Record<string, unknown> = {
              ...SUBSCRIPTION_ACTIVE,
              ...(customerId ? { stripe_customer_id: customerId } : {}),
            }

            const subscriptionId =
              typeof session.subscription === "string"
                ? session.subscription
                : session.subscription?.id ?? null

            if (subscriptionId) {
              try {
                const subscription =
                  await stripe.subscriptions.retrieve(subscriptionId)
                subscriptionPayload = {
                  ...buildSubscriptionProfileUpdatePayload(subscription),
                  ...(customerId ? { stripe_customer_id: customerId } : {}),
                }
              } catch (subErr) {
                console.error(
                  "⚠️ checkout.session.completed: subscription retrieve failed, using active fallback:",
                  subErr
                )
              }
            }

            devLog("🛠 Updating user subscription:", userId, subscriptionPayload)
            const { error: upErr } = await supabase
              .from("profiles")
              .update(subscriptionPayload as ProfileUpdate)
              .eq("id", userId)

            if (upErr) {
              console.error("ERROR:", JSON.stringify(upErr, null, 2))
            } else {
              devLog("✅ checkout.session.completed: profile updated to active")
              if (subscriptionPayload.is_pro === true) {
                await enableAllAccountsForTradeEntry(supabase, userId)
              }
              if (customerId) {
                const { error: mirrorErr } =
                  await mirrorBillingAccountsStripeCustomerId(
                    supabase,
                    userId,
                    customerId
                  )
                if (mirrorErr) {
                  console.error(
                    "mirror billing_accounts.stripe_customer_id:",
                    JSON.stringify(mirrorErr, null, 2)
                  )
                }
              }
            }
          } catch (e) {
            console.error("❌ checkout profile update crash:", e)
          }
        }

        if (userId && session.id) {
          try {
            await trackAffiliateAttributionFromCheckout({
              stripe,
              supabase,
              session,
              buyerProfileId: userId,
            })
          } catch (affErr) {
            console.error("❌ Affiliate discount tracking error:", affErr)
          }
        }
      } catch (err) {
        console.error("❌ checkout.session.completed handler error:", err)
      }
    }

    // ======================================================
    // INVOICE PAID → Pro refresh + referral ledger + referrer earnings
    // Idempotent per stripe_invoice_id.
    // TEMP: affiliate-path decision logging (console.log — visible in production).
    // ======================================================
    if (event.type === "invoice.paid") {
      try {
        const invoice = event.data.object as Stripe.Invoice & {
          subscription?: string | Stripe.Subscription | null
        }

        const customerId = stripeCustomerId(invoice.customer)
        const subscriptionRaw = invoice.subscription
        const subscriptionId =
          typeof subscriptionRaw === "string"
            ? subscriptionRaw
            : subscriptionRaw &&
                typeof subscriptionRaw === "object" &&
                "id" in subscriptionRaw
              ? (subscriptionRaw as Stripe.Subscription).id
              : null

        const status = invoice.status ?? "unknown"
        const commissionBase = resolveAffiliateCommissionBaseCents(invoice)
        const stripePriceId = extractStripePriceIdFromInvoice(invoice)

        console.log("[invoice.paid][AFFILIATE TEMP] START", {
          invoiceId: invoice.id ?? null,
          customerId,
          subscriptionId,
          status,
          currency: invoice.currency ?? null,
          billing_reason: invoice.billing_reason ?? null,
          amount_paid: invoice.amount_paid ?? null,
          total: invoice.total ?? null,
          total_excluding_tax: invoice.total_excluding_tax ?? null,
          commission_base_cents_precomputed: commissionBase.basisCents,
          commission_base_source_precomputed: commissionBase.source,
          stripe_price_id: stripePriceId,
        })

        console.log("[invoice.paid][AFFILIATE TEMP] BEFORE customerId check", {
          customerId,
        })
        if (!customerId) {
          console.log(
            "[invoice.paid][AFFILIATE TEMP] BRANCH EXIT: no customerId on invoice"
          )
          console.error(
            "[invoice.paid] no Stripe customer id on invoice object"
          )
          return new Response("OK", { status: 200 })
        }
        console.log("[invoice.paid][AFFILIATE TEMP] AFTER customerId check: OK", {
          customerId,
        })

        //----------------------------------------
        // STEP 1: Get paying user (retry — profile may lag checkout)
        //----------------------------------------

        let payingUser: Record<string, unknown> | null = null
        let lastLookupError: unknown = null

        console.log(
          "[invoice.paid][AFFILIATE TEMP] BEFORE paying-user lookup by stripe_customer_id",
          { customerId, maxAttempts: 5 }
        )

        for (let attempt = 0; attempt < 5; attempt++) {
          const { data, error: userError } = await supabase
            .from("profiles")
            .select("id, referred_by")
            .eq("stripe_customer_id", customerId)
            .maybeSingle()

          console.log(
            "[invoice.paid][AFFILIATE TEMP] customer lookup attempt result",
            {
              attempt: attempt + 1,
              customerId,
              found: Boolean(data?.id),
              profileId: data?.id ?? null,
              referred_by_raw: data?.referred_by ?? null,
              error: userError
                ? {
                    message: userError.message,
                    code: userError.code,
                    details: userError.details,
                    hint: userError.hint,
                  }
                : null,
            }
          )

          if (userError) {
            lastLookupError = userError
            console.error("[invoice.paid] profile lookup error", userError)
          }

          if (data) {
            payingUser = data as Record<string, unknown>
            break
          }

          await new Promise((res) => setTimeout(res, 1000))
        }

        console.log(
          "[invoice.paid][AFFILIATE TEMP] AFTER paying-user lookup",
          {
            customerId,
            payingUserFound: Boolean(payingUser?.id),
            payingUserId: payingUser?.id ?? null,
            referred_by: payingUser?.referred_by ?? null,
            lastLookupError:
              lastLookupError && typeof lastLookupError === "object"
                ? {
                    message: (lastLookupError as { message?: string }).message,
                    code: (lastLookupError as { code?: string }).code,
                  }
                : lastLookupError,
          }
        )

        if (!payingUser?.id) {
          console.log(
            "[invoice.paid][AFFILIATE TEMP] BRANCH EXIT: paying user profile NOT found",
            { customerId }
          )
          console.error(
            "[invoice.paid] no paying user for stripe_customer_id:",
            customerId
          )
          return new Response("OK", { status: 200 })
        }

        console.log(
          "[invoice.paid][AFFILIATE TEMP] Paying user profile found?",
          true,
          { payingUserId: payingUser.id }
        )

        try {
          if (subscriptionId) {
            const subscription = await stripe.subscriptions.retrieve(subscriptionId)
            await syncSubscriptionToProfile({
              supabase,
              subscription,
              logContext: "invoice.paid",
            })
          } else {
            const { error: proErr } = await supabase
              .from("profiles")
              .update(SUBSCRIPTION_ACTIVE)
              .eq("id", payingUser.id as string)

            if (proErr) {
              console.error("Pro refresh failed (invoice.paid)", proErr)
            }
          }
        } catch (e) {
          console.error("[invoice.paid] subscription sync crash:", e)
        }

        //----------------------------------------
        // STEP 2: Referral on payer (DB first, then Stripe metadata fallback)
        //----------------------------------------

        let referredRaw = payingUser.referred_by as string | null | undefined
        let referredBy = normalizeAffiliateCode(referredRaw)

        let subscriptionMetadata: Stripe.Metadata | null = null
        let customerMetadata: Stripe.Metadata | null = null

        if (!referredBy && subscriptionId) {
          try {
            const subscription = await stripe.subscriptions.retrieve(subscriptionId)
            subscriptionMetadata = subscription.metadata ?? null
          } catch (subMetaErr) {
            console.error("[invoice.paid] subscription metadata retrieve failed:", subMetaErr)
          }
        }

        if (!referredBy) {
          try {
            const customer = await stripe.customers.retrieve(customerId)
            if (customer && !("deleted" in customer && customer.deleted)) {
              customerMetadata = customer.metadata ?? null
            }
          } catch (custMetaErr) {
            console.error("[invoice.paid] customer metadata retrieve failed:", custMetaErr)
          }
        }

        if (!referredBy) {
          referredBy = resolveAffiliateCodeForCommission({
            profileReferredBy: referredRaw,
            subscriptionMetadata,
            customerMetadata,
          })
        }

        console.log(
          "[invoice.paid][AFFILIATE TEMP] BEFORE referred_by gate",
          {
            payingUserId: payingUser.id,
            referred_by_raw: referredRaw ?? null,
            referred_by_trimmed: referredBy,
            referred_by_empty: !referredBy,
            metadata_affiliate_code:
              readAffiliateCodeFromStripeMetadata(subscriptionMetadata) ||
              readAffiliateCodeFromStripeMetadata(customerMetadata) ||
              null,
          }
        )

        if (!referredBy) {
          console.log(
            "[invoice.paid][AFFILIATE TEMP] BRANCH EXIT: referred_by empty — skip commission",
            { payingUserId: payingUser.id, referred_by_raw: referredRaw ?? null }
          )
          return new Response("OK", { status: 200 })
        }

        // Backfill durable DB attribution when recovered from Stripe metadata.
        if (!normalizeAffiliateCode(referredRaw) && referredBy) {
          try {
            await applyAffiliateAttributionToBuyer({
              supabase,
              buyerProfileId: payingUser.id as string,
              affiliateCode: referredBy,
              source: "invoice.paid_metadata_backfill",
            })
          } catch (backfillErr) {
            console.error("[invoice.paid] referred_by backfill failed:", backfillErr)
          }
        }

        console.log(
          "[invoice.paid][AFFILIATE TEMP] AFTER referred_by gate: OK",
          { referredBy }
        )

        //----------------------------------------
        // STEP 3: Referrer profile
        //----------------------------------------

        console.log(
          "[invoice.paid][AFFILIATE TEMP] BEFORE referrer lookup",
          { referral_code_eq: referredBy }
        )

        const { data: referrer, error: refError } = await supabase
          .from("profiles")
          .select("id, referral_earnings")
          .eq("referral_code", referredBy)
          .maybeSingle()

        console.log(
          "[invoice.paid][AFFILIATE TEMP] AFTER referrer lookup",
          {
            referral_code_eq: referredBy,
            referrerFound: Boolean(referrer?.id),
            referrerId: referrer?.id ?? null,
            referrer_referral_earnings: referrer?.referral_earnings ?? null,
            error: refError
              ? {
                  message: refError.message,
                  code: refError.code,
                  details: refError.details,
                  hint: refError.hint,
                }
              : null,
          }
        )

        if (refError || !referrer?.id) {
          console.log(
            "[invoice.paid][AFFILIATE TEMP] BRANCH EXIT: referrer NOT found",
            { referredBy, refError: refError?.message ?? null }
          )
          console.error("[invoice.paid] referrer not found", refError, {
            referredBy,
          })
          return new Response("OK", { status: 200 })
        }

        console.log(
          "[invoice.paid][AFFILIATE TEMP] Referrer found?",
          true,
          { referrerId: referrer.id }
        )

        console.log(
          "[invoice.paid][AFFILIATE TEMP] BEFORE self-referral check",
          {
            referrerId: referrer.id,
            payingUserId: payingUser.id,
            isSelfReferral: referrer.id === payingUser.id,
          }
        )

        if (referrer.id === payingUser.id) {
          console.log(
            "[invoice.paid][AFFILIATE TEMP] BRANCH EXIT: self-referral",
            { userId: referrer.id }
          )
          return new Response("OK", { status: 200 })
        }

        console.log(
          "[invoice.paid][AFFILIATE TEMP] AFTER self-referral check: OK (not self)"
        )

        console.log(
          "[invoice.paid][AFFILIATE TEMP] BEFORE invoice.id check",
          { invoiceId: invoice.id ?? null }
        )

        if (!invoice.id) {
          console.log(
            "[invoice.paid][AFFILIATE TEMP] BRANCH EXIT: invoice.id missing"
          )
          console.error(
            "[invoice.paid] invoice.id missing — cannot record referral row"
          )
          return new Response("OK", { status: 200 })
        }

        console.log(
          "[invoice.paid][AFFILIATE TEMP] BEFORE duplicate invoice check",
          { stripe_invoice_id: invoice.id }
        )

        const { data: existing, error: existingError } = await supabase
          .from("referrals")
          .select("id")
          .eq("stripe_invoice_id", invoice.id)
          .maybeSingle()

        console.log(
          "[invoice.paid][AFFILIATE TEMP] AFTER duplicate invoice check",
          {
            stripe_invoice_id: invoice.id,
            duplicateFound: Boolean(existing?.id),
            existingReferralId: existing?.id ?? null,
            error: existingError
              ? {
                  message: existingError.message,
                  code: existingError.code,
                }
              : null,
          }
        )

        if (existing) {
          console.log(
            "[invoice.paid][AFFILIATE TEMP] BRANCH EXIT: duplicate stripe_invoice_id",
            { invoiceId: invoice.id, existingReferralId: existing.id }
          )
          return new Response("OK", { status: 200 })
        }

        const { count: priorCommissionCount } = await supabase
          .from("referrals")
          .select("id", { count: "exact", head: true })
          .eq("referrer_user_id", referrer.id)
          .eq("referred_user_id", payingUser.id as string)

        const isFirstCommissionForPair = (priorCommissionCount ?? 0) === 0

        //----------------------------------------
        // STEP 4: Commission base = after discounts, before tax (never amount_paid)
        //----------------------------------------

        const commissionBaseMajor = centsToMajorUnits(commissionBase.basisCents)
        const commissionRatePercent = Math.round(COMMISSION_RATE * 10000) / 100
        const currency = String(invoice.currency ?? "usd").toLowerCase()

        console.log(
          "[invoice.paid][AFFILIATE TEMP] BEFORE commission base gate",
          {
            basisCents: commissionBase.basisCents,
            source: commissionBase.source,
            commissionBaseMajor,
            currency,
            amount_paid: invoice.amount_paid ?? null,
            total: invoice.total ?? null,
            total_excluding_tax: invoice.total_excluding_tax ?? null,
            commissionBaseMajor_lte_0: commissionBaseMajor <= 0,
          }
        )

        if (
          !shouldRecordAffiliateCommission({
            invoiceStatus: status,
            commissionBaseMajor,
          })
        ) {
          console.log(
            "[invoice.paid][AFFILIATE TEMP] BRANCH EXIT: commission not recordable",
            {
              status,
              commissionBaseMajor,
              basisCents: commissionBase.basisCents,
              source: commissionBase.source,
            }
          )
          return new Response("OK", { status: 200 })
        }

        const commission = calculateAffiliateCommission(commissionBaseMajor)

        console.log(
          "[invoice.paid][AFFILIATE TEMP] AFTER commission calculation",
          {
            commissionBaseMajor,
            commissionRate: COMMISSION_RATE,
            commissionRatePercent,
            commission,
          }
        )

        //----------------------------------------
        // STEP 5: Insert referral
        //----------------------------------------

        const insertPayload = {
          referrer_user_id: referrer.id,
          referred_user_id: payingUser.id as string,
          amount_earned: commission,
          transaction_amount: commissionBaseMajor,
          commission_rate: commissionRatePercent,
          currency,
          stripe_customer_id: customerId,
          stripe_subscription_id: subscriptionId,
          stripe_invoice_id: invoice.id,
          stripe_price_id: stripePriceId,
        }

        console.log(
          "[invoice.paid][AFFILIATE TEMP] BEFORE referrals INSERT",
          insertPayload
        )

        const { data: insertedRows, error: insertError } = await supabase
          .from("referrals")
          .insert(insertPayload)
          .select("id, amount_earned, transaction_amount, stripe_invoice_id")

        console.log(
          "[invoice.paid][AFFILIATE TEMP] AFTER referrals INSERT",
          {
            ok: !insertError,
            insertedRows: insertedRows ?? null,
            error: insertError
              ? {
                  message: insertError.message,
                  code: insertError.code,
                  details: insertError.details,
                  hint: insertError.hint,
                }
              : null,
          }
        )

        if (insertError) {
          console.log(
            "[invoice.paid][AFFILIATE TEMP] BRANCH EXIT: referrals INSERT failed",
            {
              message: insertError.message,
              code: insertError.code,
              details: insertError.details,
              hint: insertError.hint,
            }
          )
          console.error("[invoice.paid] referrals insert failed", insertError)
          return new Response("OK", { status: 200 })
        }

        //----------------------------------------
        // STEP 6: Referrer total
        //----------------------------------------

        const previousEarnings = Number(referrer.referral_earnings || 0)
        const newTotal = previousEarnings + commission

        console.log(
          "[invoice.paid][AFFILIATE TEMP] BEFORE profiles.referral_earnings update",
          {
            referrerId: referrer.id,
            previousEarnings,
            commission,
            newTotal,
          }
        )

        const { data: earningsUpdateRows, error: updateError } = await supabase
          .from("profiles")
          .update({ referral_earnings: newTotal })
          .eq("id", referrer.id as string)
          .select("id, referral_earnings")

        console.log(
          "[invoice.paid][AFFILIATE TEMP] AFTER profiles.referral_earnings update",
          {
            ok: !updateError,
            rows: earningsUpdateRows ?? null,
            error: updateError
              ? {
                  message: updateError.message,
                  code: updateError.code,
                  details: updateError.details,
                  hint: updateError.hint,
                }
              : null,
          }
        )

        if (updateError) {
          console.log(
            "[invoice.paid][AFFILIATE TEMP] BRANCH EXIT: referral_earnings update failed",
            {
              message: updateError.message,
              code: updateError.code,
            }
          )
          console.error(
            "[invoice.paid] referrer referral_earnings update failed",
            updateError
          )
          return new Response("OK", { status: 200 })
        }

        console.log(
          "[invoice.paid][AFFILIATE TEMP] SUCCESS — commission recorded",
          {
            invoiceId: invoice.id,
            referrerId: referrer.id,
            payingUserId: payingUser.id,
            transaction_amount: commissionBaseMajor,
            amount_earned: commission,
            referral_earnings: newTotal,
          }
        )

        if (isFirstCommissionForPair) {
          try {
            await createAffiliateCommissionNotification(supabase, {
              affiliateUserId: referrer.id as string,
              referredUserId: payingUser.id as string,
              commissionAmount: commission,
            })
          } catch (notifErr) {
            console.error("[invoice.paid] affiliate commission notification failed:", notifErr)
          }
        }
      } catch (err) {
        console.log("[invoice.paid][AFFILIATE TEMP] CATCH handler error", {
          err: err instanceof Error ? err.message : String(err),
          stack: err instanceof Error ? err.stack : null,
        })
        console.error("[invoice.paid] handler error:", err)
      }
    }

    // ======================================================
    // SUBSCRIPTION CREATED/UPDATED → sync membership fields
    // ======================================================
    if (
      event.type === "customer.subscription.created" ||
      event.type === "customer.subscription.updated"
    ) {
      try {
        const subscription = event.data.object as Stripe.Subscription
        await syncSubscriptionToProfile({
          supabase,
          subscription,
          logContext: event.type,
        })
      } catch (err) {
        console.error("❌ subscription sync handler error:", err)
      }
    }

    // ======================================================
    // ❌ SUBSCRIPTION DELETED → revoke Pro
    // ======================================================
    if (event.type === "customer.subscription.deleted") {
      devLog("📦 Processing customer.subscription.deleted")

      try {
        const sub = event.data.object as Stripe.Subscription
        const customerId = stripeCustomerId(sub.customer)

        if (!customerId) {
          devLog("❌ subscription.deleted: no customer id")
        } else {
          const { data: profile, error: findErr } = await supabase
            .from("profiles")
            .select("id")
            .eq("stripe_customer_id", customerId)
            .maybeSingle()

          if (findErr) {
            devLog("❌ subscription.deleted profile lookup error:", findErr)
          } else if (!profile?.id) {
            devLog(
              "❌ No profile found for stripe_customer_id (subscription.deleted):",
              customerId
            )
          } else {
            try {
              const { error: upErr } = await supabase
                .from("profiles")
                .update({
                  ...SUBSCRIPTION_INACTIVE,
                  cancel_at: null,
                })
                .eq("id", profile.id)

              if (upErr) {
                console.error("ERROR:", JSON.stringify(upErr, null, 2))
              } else {
                devLog("✅ Pro revoked (customer.subscription.deleted)")
              }
            } catch (e) {
              console.error("❌ subscription.deleted update crash:", e)
            }
          }
        }
      } catch (err) {
        console.error("❌ cancel error:", err)
      }
    }

    return new Response("OK", { status: 200 })
  } catch (err) {
    console.error("❌ WEBHOOK ERROR:", err)
    console.error(
      "ERROR:",
      JSON.stringify(
        err instanceof Error
          ? { message: err.message, name: err.name }
          : err,
        null,
        2
      )
    )
    return new Response("Webhook error", { status: 500 })
  }
}
