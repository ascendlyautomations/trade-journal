import Stripe from "stripe"
import { createClient, type SupabaseClient } from "@supabase/supabase-js"

export const runtime = "nodejs"

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY as string)

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

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
      console.log("❌ Buyer referred_by update error:", buyerRefErr)
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
        console.log("❌ referral_count update error:", refUpErr)
      } else {
        console.log("✅ referral_count incremented for:", affiliate.code)
      }
    }

    break
  }
}

export async function POST(req: Request) {
  try {
    const body = await req.text()
    const sig = req.headers.get("stripe-signature")

    if (!sig) {
      console.error("❌ No signature")
      return new Response("No signature", { status: 400 })
    }

    let event: Stripe.Event

    try {
      event = stripe.webhooks.constructEvent(
        body,
        sig,
        process.env.STRIPE_WEBHOOK_SECRET as string
      )
    } catch (err) {
      console.error("❌ VERIFY FAILED:", err)
      return new Response("Invalid signature", { status: 400 })
    }

    console.log("🔥 WEBHOOK HIT:", event.type)

    // ======================================================
    // ✅ CHECKOUT SESSION COMPLETED → link customer + Pro
    // ======================================================
    if (event.type === "checkout.session.completed") {
      console.log("📦 Processing checkout.session.completed")

      try {
        const session = event.data.object as Stripe.Checkout.Session
        const customerId = stripeCustomerId(session.customer)

        console.log("🔥 CHECKOUT COMPLETE — customerId:", customerId)

        let profileId: string | null = null

        if (customerId) {
          const { data: byCustomer, error: lookupErr } = await supabase
            .from("profiles")
            .select("id")
            .eq("stripe_customer_id", customerId)
            .maybeSingle()

          if (lookupErr) {
            console.log("⚠️ checkout profile lookup by customer error:", lookupErr)
          }
          if (byCustomer?.id) {
            profileId = byCustomer.id
            console.log("👤 Profile resolved via stripe_customer_id:", profileId)
          }
        }

        if (!profileId) {
          const metaUserId =
            session.metadata?.userId ?? session.metadata?.user_id ?? null
          if (metaUserId) {
            profileId = metaUserId
            console.log("👤 Profile resolved via session metadata user id:", profileId)
          }
        }

        if (!profileId) {
          console.log(
            "❌ checkout.session.completed: could not resolve profile (no customer match, no metadata user id)"
          )
        } else if (!customerId) {
          console.log("❌ checkout.session.completed: missing customer id on session")
          try {
            const { error: upErr } = await supabase
              .from("profiles")
              .update({
                is_pro: true,
                subscription_status: "active",
              })
              .eq("id", profileId)

            if (upErr) {
              console.log("❌ Pro update error (no customer to store):", upErr)
            } else {
              console.log("✅ Pro activated (no stripe_customer_id on session)")
            }
          } catch (e) {
            console.error("❌ checkout Pro update crash:", e)
          }
        } else {
          try {
            const { error: upErr } = await supabase
              .from("profiles")
              .update({
                stripe_customer_id: customerId,
                is_pro: true,
                subscription_status: "active",
              })
              .eq("id", profileId)

            if (upErr) {
              console.log("❌ checkout profile update error:", upErr)
            } else {
              console.log("✅ USER LINKED + UPGRADED (checkout.session.completed)")
            }
          } catch (e) {
            console.error("❌ checkout profile update crash:", e)
          }
        }

        if (profileId && session.id) {
          try {
            await trackAffiliateFromManualCheckoutDiscount({
              stripe,
              supabase,
              sessionId: session.id,
              buyerProfileId: profileId,
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
    // 💰 INVOICE PAID → keep Pro active + referral earnings
    // ======================================================
    if (event.type === "invoice.paid") {
      console.log("📦 Processing invoice.paid")

      try {
        const invoice = event.data.object as Stripe.Invoice

        console.log("💰 INVOICE RECEIVED")

        const customerId = stripeCustomerId(invoice.customer)

        if (!customerId) {
          console.log("❌ No customer ID")
        } else {
          let buyer: Record<string, unknown> | null = null

          for (let i = 0; i < 5; i++) {
            const { data } = await supabase
              .from("profiles")
              .select("*")
              .eq("stripe_customer_id", customerId)
              .single()

            if (data) {
              buyer = data as Record<string, unknown>
              break
            }

            console.log(`⏳ Waiting for profile... attempt ${i + 1}`)

            await new Promise((res) => setTimeout(res, 1000))
          }

          if (!buyer) {
            console.log("❌ No buyer found after retries (invoice.paid)")
          } else {
            console.log("👤 BUYER FOUND:", buyer.id)

            try {
              const { error: proErr } = await supabase
                .from("profiles")
                .update({
                  is_pro: true,
                  subscription_status: "active",
                })
                .eq("id", buyer.id as string)

              if (proErr) {
                console.log("❌ invoice.paid Pro refresh error:", proErr)
              } else {
                console.log("✅ Pro refreshed (invoice.paid renewal)")
              }
            } catch (e) {
              console.error("❌ invoice.paid Pro refresh crash:", e)
            }

            const referralCode = buyer.referred_by as
              | string
              | null
              | undefined

            if (!referralCode) {
              console.log("❌ No referral on buyer")
            } else {
              const { data: referrer } = await supabase
                .from("profiles")
                .select("*")
                .eq("referral_code", referralCode)
                .single()

              if (!referrer) {
                console.log("❌ No referrer found")
              } else {
                try {
                  const amountPaid = (invoice.amount_paid || 0) / 100
                  const commission = amountPaid * 0.18

                  const { error: earnErr } = await supabase
                    .from("profiles")
                    .update({
                      referral_earnings:
                        Number(referrer.referral_earnings || 0) + commission,
                    })
                    .eq("id", referrer.id)

                  if (earnErr) {
                    console.log("❌ referral earnings update error:", earnErr)
                  } else {
                    console.log("✅ EARNINGS UPDATED")
                  }
                } catch (e) {
                  console.error("❌ referral earnings crash:", e)
                }
              }
            }
          }
        }
      } catch (err) {
        console.log("❌ EARNINGS ERROR:", err)
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
                .update({
                  is_pro: false,
                  subscription_status: "inactive",
                })
                .eq("id", profile.id)

              if (upErr) {
                console.log("❌ subscription.deleted update error:", upErr)
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

    return new Response("OK")
  } catch (err) {
    console.error("🔥 WEBHOOK CRASH:", err)
    return new Response("OK")
  }
}
