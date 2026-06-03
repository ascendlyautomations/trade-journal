

import Stripe from "stripe"
import { createClient, type SupabaseClient } from "@supabase/supabase-js"

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

  console.log(
    "🎟️ checkout: resolving manual promotion codes for session",
    sessionId
  )

  let sessionWithDiscounts: Stripe.Checkout.Session
  try {
    sessionWithDiscounts = await stripe.checkout.sessions.retrieve(sessionId, {
      expand: ["total_details.breakdown.discounts", "discounts"],
    })
  } catch (e) {
    console.log("⚠️ checkout sessions.retrieve (discounts) failed:", e)
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
    console.log(
      "ℹ️ No promotion code discount on checkout — skip affiliate attribution"
    )
    return
  }

  console.log("🎟️ Promotion code ids from checkout:", [...promoIds])

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
        console.log("⚠️ promotionCodes.retrieve failed:", promoId, e)
      }
    }

    if (!affiliate) {
      console.log("⚠️ No affiliate row for promotion id:", promoId)
      continue
    }

    if (affiliate.user_id === buyerProfileId) {
      console.log("⚠️ Skip self-referral (buyer is affiliate owner)")
      continue
    }

    const { error: buyerRefErr } = await supabase
      .from("profiles")
      .update({ referred_by: affiliate.code })
      .eq("id", buyerProfileId)

    if (buyerRefErr) {
      console.error("ERROR:", JSON.stringify(buyerRefErr, null, 2))
    } else {
      console.log("✅ Buyer referred_by set from manual promo:", affiliate.code)
    }

    const { data: referrerProfile, error: refFetchErr } = await supabase
      .from("profiles")
      .select("id, referral_count")
      .eq("id", affiliate.user_id)
      .maybeSingle()

    if (refFetchErr) {
      console.log("❌ Referrer profile fetch error:", refFetchErr)
    } else if (!referrerProfile?.id) {
      console.log(
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
        console.log("✅ referral_count incremented for:", affiliate.code)
      }
    }

    break
  }
}

export async function POST(req: Request) {
  console.log("🔥 WEBHOOK HIT")
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
      console.log(
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

    console.log("📩 Event received:", event.type)
    console.log("📩 Stripe event:", event.type)

    switch (event.type) {
      case "checkout.session.completed":
      case "invoice.payment_succeeded":
      case "customer.subscription.created":
        console.log("➡️ Handling event:", event.type)
        break
      default:
        break
    }

    // ======================================================
    // ✅ CHECKOUT SESSION COMPLETED → link customer + Pro
    // ======================================================
    if (event.type === "checkout.session.completed") {
      console.log("📦 Processing checkout.session.completed")

      try {
        const session = event.data.object as Stripe.Checkout.Session
        const customerId = stripeCustomerId(session.customer)

        console.log("🔥 CHECKOUT COMPLETE — customerId:", customerId)

        let userId: string | null =
          session.metadata?.user_id ||
          session.metadata?.userId ||
          null
        console.log("👤 User ID from metadata:", userId)

        if (!userId && customerId) {
          const { data: byCustomer, error: lookupErr } = await supabase
            .from("profiles")
            .select("id")
            .eq("stripe_customer_id", customerId)
            .maybeSingle()

          if (lookupErr) {
            console.log("⚠️ checkout profile lookup by customer error:", lookupErr)
          }
          if (byCustomer?.id) {
            userId = byCustomer.id
            console.log("👤 Profile resolved via stripe_customer_id:", userId)
          }
        }

        if (!userId) {
          console.log(
            "❌ checkout.session.completed: could not resolve user (no metadata user id, no stripe_customer_id match)"
          )
        } else {
          console.log("🔥 Activating subscription for:", userId)

          try {
            console.log("🛠 Updating user to PRO:", userId)
            const { error: upErr } = await supabase
              .from("profiles")
              .update({
                ...SUBSCRIPTION_ACTIVE,
                ...(customerId ? { stripe_customer_id: customerId } : {}),
              })
              .eq("id", userId)

            if (upErr) {
              console.error("ERROR:", JSON.stringify(upErr, null, 2))
            } else {
              console.log("✅ checkout.session.completed: profile updated to active")
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

        const amountPaidCents = Number(invoice.amount_paid ?? 0)
        const totalCents = Number(invoice.total ?? 0)
        const status = invoice.status ?? "unknown"

        console.log("[invoice.paid] event received", {
          invoiceId: invoice.id,
          customerId,
          subscriptionId,
          status,
          currency: invoice.currency,
          billing_reason: invoice.billing_reason,
          amount_paid_cents: amountPaidCents,
          total_cents: totalCents,
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
            .select("*")
            .eq("stripe_customer_id", customerId)
            .maybeSingle()

          if (userError) {
            console.error("[invoice.paid] profile lookup error", userError)
          }

          if (data) {
            payingUser = data as Record<string, unknown>
            break
          }

          console.log(
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

        console.log("[invoice.paid] paying user:", payingUser.id)

        try {
          const { error: proErr } = await supabase
            .from("profiles")
            .update(SUBSCRIPTION_ACTIVE)
            .eq("id", payingUser.id as string)

          if (proErr) {
            console.error("Pro refresh failed (invoice.paid)", proErr)
          } else {
            console.log("[invoice.paid] Pro subscription_status refreshed")
          }
        } catch (e) {
          console.error("[invoice.paid] Pro refresh crash:", e)
        }

        //----------------------------------------
        // STEP 2: Referral on payer
        //----------------------------------------

        const referredRaw = payingUser.referred_by as string | null | undefined
        const referredBy =
          referredRaw != null ? String(referredRaw).trim() : ""

        if (!referredBy) {
          console.log(
            "[invoice.paid] no referral on payer (referred_by empty), skip commission"
          )
          return new Response("OK", { status: 200 })
        }

        console.log("🔗 Referral code used:", referredBy)

        //----------------------------------------
        // STEP 3: Referrer profile
        //----------------------------------------

        const { data: referrer, error: refError } = await supabase
          .from("profiles")
          .select("*")
          .eq("referral_code", referredBy)
          .maybeSingle()

        if (refError || !referrer?.id) {
          console.error("[invoice.paid] referrer not found", refError, {
            referredBy,
          })
          return new Response("OK", { status: 200 })
        }

        if (referrer.id === payingUser.id) {
          console.log("[invoice.paid] skip self-referral")
          return new Response("OK", { status: 200 })
        }

        console.log("[invoice.paid] referrer:", referrer.id)

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
          console.log(
            "[invoice.paid] referral already recorded for invoice, skipping:",
            invoice.id
          )
          return new Response("OK", { status: 200 })
        }

        //----------------------------------------
        // STEP 4: Commission basis (prefer amount_paid; fallback for edge cases)
        //----------------------------------------

        let basisCents = amountPaidCents
        if (basisCents <= 0 && status === "paid" && totalCents > 0) {
          console.log(
            "amount_paid was 0 but invoice is paid with total > 0 — using total as commission basis (cents):",
            totalCents
          )
          basisCents = totalCents
        }

        const amountPaid = basisCents / 100

        console.log(
          "[invoice.paid] commission basis (major units, after cents/100):",
          amountPaid,
          invoice.currency
        )

        if (amountPaid <= 0) {
          console.log(
            "[invoice.paid] commission basis is 0 — skip row (trial, $0, or unpaid shape)"
          )
          return new Response("OK", { status: 200 })
        }

        const commission = Math.round(amountPaid * 0.18 * 100) / 100

        console.log("[invoice.paid] commission 18%:", commission)

        //----------------------------------------
        // STEP 5: Insert referral
        //----------------------------------------

        const { error: insertError } = await supabase.from("referrals").insert({
          referrer_user_id: referrer.id,
          referred_user_id: payingUser.id as string,
          amount_earned: commission,
          stripe_customer_id: customerId,
          stripe_subscription_id: subscriptionId,
          stripe_invoice_id: invoice.id,
        })

        if (insertError) {
          console.error("[invoice.paid] referrals insert failed", insertError)
          return new Response("OK", { status: 200 })
        }

        console.log("[invoice.paid] referral row inserted", {
          amount_earned: commission,
          stripe_invoice_id: invoice.id,
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

        console.log("[invoice.paid] referrer referral_earnings →", newTotal)
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
        const customerId = stripeCustomerId(subscription.customer)

        if (!customerId) {
          console.log(
            "❌ subscription sync: missing customer id",
            event.type
          )
        } else {
          const { data: profile, error: findErr } = await supabase
            .from("profiles")
            .select("id")
            .eq("stripe_customer_id", customerId)
            .maybeSingle()

          if (findErr) {
            console.error(
              "❌ subscription sync: profile lookup error:",
              findErr,
              { customerId, eventType: event.type }
            )
          } else if (!profile?.id) {
            console.error(
              "❌ No profile found for stripe_customer_id (subscription sync):",
              customerId
            )
          } else {
            const updatePayload: Record<string, unknown> = {
              subscription_status: subscription.status,
              cancel_at_period_end: subscription.cancel_at_period_end ?? false,
            }

            // Handle trial end
            if (subscription.trial_end) {
              updatePayload.trial_end = new Date(subscription.trial_end * 1000)
            }

            // Handle period end (important for canceling users)
            if (subscription.current_period_end) {
              updatePayload.current_period_end = new Date(
                subscription.current_period_end * 1000
              )
            }

            // If still in trial, ensure current_period_end is set correctly
            if (!subscription.current_period_end && subscription.trial_end) {
              updatePayload.current_period_end = new Date(
                subscription.trial_end * 1000
              )
            }

            console.log("[subscription sync] applying update:", {
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
              console.error("❌ Failed to update subscription:", upErr, {
                customerId,
                profileId: profile.id,
              })
            } else if (!updatedRows?.length) {
              console.error(
                "❌ subscription sync: 0 rows updated",
                { customerId, profileId: profile.id }
              )
            } else {
              console.log("✅ Subscription synced successfully", {
                customerId,
                profileId: profile.id,
                rowsUpdated: updatedRows.length,
              })
            }
          }
        }
      } catch (err) {
        console.error("❌ subscription sync handler error:", err)
      }
    }

    // ======================================================
    // ❌ SUBSCRIPTION DELETED → revoke Pro
    // ======================================================
    if (event.type === "customer.subscription.deleted") {
      console.log("📦 Processing customer.subscription.deleted")

      try {
        const sub = event.data.object as Stripe.Subscription
        const customerId = stripeCustomerId(sub.customer)

        if (!customerId) {
          console.log("❌ subscription.deleted: no customer id")
        } else {
          const { data: profile, error: findErr } = await supabase
            .from("profiles")
            .select("id")
            .eq("stripe_customer_id", customerId)
            .maybeSingle()

          if (findErr) {
            console.log("❌ subscription.deleted profile lookup error:", findErr)
          } else if (!profile?.id) {
            console.log(
              "❌ No profile found for stripe_customer_id (subscription.deleted):",
              customerId
            )
          } else {
            try {
              const { error: upErr } = await supabase
                .from("profiles")
                .update(SUBSCRIPTION_INACTIVE)
                .eq("id", profile.id)

              if (upErr) {
                console.error("ERROR:", JSON.stringify(upErr, null, 2))
              } else {
                console.log("✅ Pro revoked (customer.subscription.deleted)")
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
