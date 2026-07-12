

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
  createAffiliateCommissionNotification,
  createAffiliateReferralNotification,
} from "@/lib/server/affiliateReferralNotifications"
import { resolveTraxProBillingIntervalFromStripePriceId } from "@/lib/traxProBillingPlans.server"
import { devLog } from "@/lib/devLog"

export const runtime = "nodejs"

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY as string)

const supabase = createClient(
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
  supabase: SupabaseClient
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
    .update(updatePayload)
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
  return true
}

/**
 * When the customer enters a promotion code in Checkout, attribute affiliate
 * (referred_by + referral_count) — no auto-applied codes at session create.
 */
async function trackAffiliateFromManualCheckoutDiscount(params: {
  stripe: Stripe
  supabase: SupabaseClient
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

    if (affiliate.user_id === buyerProfileId) {
      devLog("⚠️ Skip self-referral (buyer is affiliate owner)")
      continue
    }

    const { error: buyerRefErr } = await supabase
      .from("profiles")
      .update({ referred_by: affiliate.code })
      .eq("id", buyerProfileId)

    if (buyerRefErr) {
      console.error("ERROR:", JSON.stringify(buyerRefErr, null, 2))
    } else {
      devLog("✅ Buyer referred_by set from manual promo:", affiliate.code)
      try {
        await createAffiliateReferralNotification(supabase, {
          affiliateUserId: affiliate.user_id,
          referredUserId: buyerProfileId,
        })
      } catch (notifErr) {
        console.error("[checkout] affiliate referral notification failed:", notifErr)
      }
    }

    const { data: referrerProfile, error: refFetchErr } = await supabase
      .from("profiles")
      .select("id, referral_count")
      .eq("id", affiliate.user_id)
      .maybeSingle()

    if (refFetchErr) {
      devLog("❌ Referrer profile fetch error:", refFetchErr)
    } else if (!referrerProfile?.id) {
      devLog(
        "❌ Referrer profile missing for affiliate.user_id:",
        affiliate.user_id
      )
    } else {
      const { error: refUpErr } = await supabase
        .from("profiles")
        .update({
          referral_count: Number(referrerProfile.referral_count || 0) + 1,
        })
        .eq("id", referrerProfile.id)

      if (refUpErr) {
        console.error("ERROR:", JSON.stringify(refUpErr, null, 2))
      } else {
        devLog("✅ referral_count incremented for:", affiliate.code)
      }
    }

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
              .update(subscriptionPayload)
              .eq("id", userId)

            if (upErr) {
              console.error("ERROR:", JSON.stringify(upErr, null, 2))
            } else {
              devLog("✅ checkout.session.completed: profile updated to active")
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
            await trackAffiliateFromManualCheckoutDiscount({
              stripe,
              supabase,
              sessionId: session.id,
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
    // Idempotent per stripe_invoice_id. Detailed logs for commission debugging.
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

        const totalCents = Number(invoice.total ?? 0)
        const status = invoice.status ?? "unknown"
        const commissionBase = resolveAffiliateCommissionBaseCents(invoice)
        const stripePriceId = extractStripePriceIdFromInvoice(invoice)

        devLog("[invoice.paid] event received", {
          invoiceId: invoice.id,
          customerId,
          subscriptionId,
          status,
          currency: invoice.currency,
          billing_reason: invoice.billing_reason,
          amount_paid_cents: Number(invoice.amount_paid ?? 0),
          total_cents: totalCents,
          total_excluding_tax_cents: invoice.total_excluding_tax,
          commission_base_cents: commissionBase.basisCents,
          commission_base_source: commissionBase.source,
          stripe_price_id: stripePriceId,
          subtotal: invoice.subtotal,
          amount_due: invoice.amount_due,
        })

        if (!customerId) {
          console.error(
            "[invoice.paid] no Stripe customer id on invoice object"
          )
          return new Response("OK", { status: 200 })
        }

        //----------------------------------------
        // STEP 1: Get paying user (retry — profile may lag checkout)
        //----------------------------------------

        let payingUser: Record<string, unknown> | null = null

        for (let attempt = 0; attempt < 5; attempt++) {
          const { data, error: userError } = await supabase
            .from("profiles")
            .select("id, referred_by")
            .eq("stripe_customer_id", customerId)
            .maybeSingle()

          if (userError) {
            console.error("[invoice.paid] profile lookup error", userError)
          }

          if (data) {
            payingUser = data as Record<string, unknown>
            break
          }

          devLog(
            `Waiting for profile stripe_customer_id=${customerId} attempt ${attempt + 1}/5`
          )
          await new Promise((res) => setTimeout(res, 1000))
        }

        if (!payingUser?.id) {
          console.error(
            "[invoice.paid] no paying user for stripe_customer_id:",
            customerId
          )
          return new Response("OK", { status: 200 })
        }

        devLog("[invoice.paid] paying user:", payingUser.id)

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
            } else {
              devLog("[invoice.paid] Pro subscription_status refreshed")
            }
          }
        } catch (e) {
          console.error("[invoice.paid] subscription sync crash:", e)
        }

        //----------------------------------------
        // STEP 2: Referral on payer
        //----------------------------------------

        const referredRaw = payingUser.referred_by as string | null | undefined
        const referredBy =
          referredRaw != null ? String(referredRaw).trim() : ""

        if (!referredBy) {
          devLog(
            "[invoice.paid] no referral on payer (referred_by empty), skip commission"
          )
          return new Response("OK", { status: 200 })
        }

        devLog("🔗 Referral code used:", referredBy)

        //----------------------------------------
        // STEP 3: Referrer profile
        //----------------------------------------

        const { data: referrer, error: refError } = await supabase
          .from("profiles")
          .select("id, referral_earnings")
          .eq("referral_code", referredBy)
          .maybeSingle()

        if (refError || !referrer?.id) {
          console.error("[invoice.paid] referrer not found", refError, {
            referredBy,
          })
          return new Response("OK", { status: 200 })
        }

        if (referrer.id === payingUser.id) {
          devLog("[invoice.paid] skip self-referral")
          return new Response("OK", { status: 200 })
        }

        devLog("[invoice.paid] referrer:", referrer.id)

        if (!invoice.id) {
          console.error(
            "[invoice.paid] invoice.id missing — cannot record referral row"
          )
          return new Response("OK", { status: 200 })
        }

        const { data: existing } = await supabase
          .from("referrals")
          .select("id")
          .eq("stripe_invoice_id", invoice.id)
          .maybeSingle()

        if (existing) {
          devLog(
            "[invoice.paid] referral already recorded for invoice, skipping:",
            invoice.id
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

        devLog(
          "[invoice.paid] commission base (major units, after discounts, before tax):",
          commissionBaseMajor,
          currency,
          commissionBase.source
        )

        if (commissionBaseMajor <= 0) {
          devLog(
            "[invoice.paid] commission base is 0 — skip row (trial, $0, or unpaid shape)"
          )
          return new Response("OK", { status: 200 })
        }

        const commission = calculateAffiliateCommission(commissionBaseMajor)

        devLog("[invoice.paid] commission 18%:", commission)

        //----------------------------------------
        // STEP 5: Insert referral
        //----------------------------------------

        const { error: insertError } = await supabase.from("referrals").insert({
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
        })

        if (insertError) {
          console.error("[invoice.paid] referrals insert failed", insertError)
          return new Response("OK", { status: 200 })
        }

        devLog("[invoice.paid] referral row inserted", {
          transaction_amount: commissionBaseMajor,
          commission_rate: commissionRatePercent,
          amount_earned: commission,
          currency,
          stripe_invoice_id: invoice.id,
          stripe_subscription_id: subscriptionId,
          stripe_customer_id: customerId,
          stripe_price_id: stripePriceId,
          commission_base_source: commissionBase.source,
        })

        //----------------------------------------
        // STEP 6: Referrer total
        //----------------------------------------

        const newTotal = Number(referrer.referral_earnings || 0) + commission

        const { error: updateError } = await supabase
          .from("profiles")
          .update({ referral_earnings: newTotal })
          .eq("id", referrer.id as string)

        if (updateError) {
          console.error(
            "[invoice.paid] referrer referral_earnings update failed",
            updateError
          )
          return new Response("OK", { status: 200 })
        }

        devLog("[invoice.paid] referrer referral_earnings →", newTotal)

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
