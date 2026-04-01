import Stripe from "stripe"
import { createClient } from "@supabase/supabase-js"

export const runtime = "nodejs"

// 🔥 INIT STRIPE
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY as string)

// 🔥 INIT SUPABASE (SERVICE ROLE)
const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function POST(req: Request) {
  console.log("🚀 WEBHOOK HIT")

  try {
    const body = await req.text()
    const sig = req.headers.get("stripe-signature")

    if (!sig) {
      console.error("❌ No signature")
      return new Response("No signature", { status: 400 })
    }

    let event: Stripe.Event

    // 🔐 VERIFY STRIPE SIGNATURE
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

    console.log("✅ VERIFIED EVENT:", event.type)

    // ======================================================
    // 🎯 HANDLE EVENTS
    // ======================================================

    // ✅ CHECKOUT COMPLETED (attach customer ID + referral)
    if (event.type === "checkout.session.completed") {
      try {
        const session = event.data.object as Stripe.Checkout.Session
        const userId = session.metadata?.userId
        const referralCode = session.metadata?.referralCode

        console.log("📦 METADATA:", session.metadata)

        if (!userId || !referralCode) {
          console.log("⏭ Missing referral data")
        } else {
          const { data: affiliate, error: affiliateError } = await supabase
            .from("affiliates")
            .select("*")
            .eq("code", referralCode)
            .single()

          if (affiliateError || !affiliate) {
            console.log("❌ Affiliate not found", affiliateError)
          } else {
            await supabase.from("referrals").insert({
              referred_user_id: userId,
              affiliate_id: affiliate.id,
              code: referralCode,
            })

            console.log("🔥 Referral saved")
          }
        }
      } catch (err) {
        console.error("❌ checkout.session.completed crash:", err)
      }
    }

    // 💰 INVOICE PAID (main trigger for PRO + revenue)
    else if (event.type === "invoice.paid") {
      try {
        const invoice = event.data.object as Stripe.Invoice

        const amountPaid = invoice.amount_paid / 100
        const customerId = invoice.customer as string

        console.log("💰 PAYMENT:", amountPaid)
        console.log("🔑 CUSTOMER:", customerId)

        const { data: user, error: userError } = await supabase
          .from("profiles")
          .select("*")
          .eq("stripe_customer_id", customerId)
          .single()

        if (userError || !user) {
          console.log("❌ User not found", userError)
        } else {
          console.log("👤 USER FOUND:", user.id)

          const { data: referrals, error: referralError } = await supabase
            .from("referrals")
            .select("*")
            .eq("referred_user_id", user.id)

          if (referralError) {
            console.error("❌ REFERRAL FETCH ERROR:", referralError)
          } else {
            console.log("🔎 REFERRALS:", referrals)

            const referral = referrals?.[0]

            if (!referral) {
              console.log("⏭ No referral found")
            } else {
              // STEP 2: UPDATE REFERRAL REVENUE
              const newReferralRevenue = (referral.revenue || 0) + amountPaid

              await supabase
                .from("referrals")
                .update({ revenue: newReferralRevenue })
                .eq("id", referral.id)

              console.log("🔥 Referral revenue updated:", newReferralRevenue)

              // STEP 3: UPDATE AFFILIATE PROFILE
              const { data: affiliate, error: affiliateError } = await supabase
                .from("profiles")
                .select("*")
                .eq("id", referral.affiliate_id)
                .single()

              if (affiliateError || !affiliate) {
                console.log("❌ Affiliate profile not found", affiliateError)
              } else {
                const newTotalRevenue =
                  (affiliate.referral_revenue || 0) + amountPaid

                await supabase
                  .from("profiles")
                  .update({
                    referral_revenue: newTotalRevenue,
                  })
                  .eq("id", affiliate.id)

                console.log("💰 Affiliate total revenue:", newTotalRevenue)

                const { count } = await supabase
                  .from("referrals")
                  .select("*", { count: "exact", head: true })
                  .eq("affiliate_id", affiliate.id)

                await supabase
                  .from("profiles")
                  .update({
                    referral_count: count || 0,
                  })
                  .eq("id", affiliate.id)

                console.log("👥 Referral count updated:", count)
              }
            }
          }
        }
      } catch (err) {
        console.error("❌ invoice.paid crash:", err)
      }
    }

    // 🔁 SUBSCRIPTION UPDATED (cancel scheduled / resumed)
    else if (event.type === "customer.subscription.updated") {
      try {
        const sub = event.data.object as Stripe.Subscription
        const customerId = sub.customer as string

        console.log("🔁 SUB UPDATED:", customerId)
        console.log("cancel_at_period_end:", sub.cancel_at_period_end)
        console.log("status:", sub.status)

        const { data: user, error: fetchError } = await supabase
          .from("profiles")
          .select("*")
          .eq("stripe_customer_id", customerId)
          .single()

        if (fetchError || !user) {
          console.error("❌ USER NOT FOUND:", customerId)
        } else {
          // ⚠️ Scheduled cancel
          if (sub.cancel_at_period_end === true) {
            const { error } = await supabase
              .from("profiles")
              .update({
                subscription_status: "canceling",
              })
              .eq("id", user.id)

            if (error) {
              console.error("❌ FAILED TO SET CANCELING:", error)
            } else {
              console.log("⚠️ USER SET TO CANCELING")
            }
          }

          // ✅ Resumed subscription
          if (sub.cancel_at_period_end === false && sub.status === "active") {
            const { error } = await supabase
              .from("profiles")
              .update({
                subscription_status: "active",
              })
              .eq("id", user.id)

            if (error) {
              console.error("❌ FAILED TO SET ACTIVE:", error)
            } else {
              console.log("✅ USER BACK TO ACTIVE")
            }
          }
        }
      } catch (err) {
        console.error("❌ customer.subscription.updated crash:", err)
      }
    }

    // ❌ FULLY CANCELED (end of billing period)
    else if (event.type === "customer.subscription.deleted") {
      try {
        const sub = event.data.object as Stripe.Subscription
        const customerId = sub.customer as string

        console.log("❌ SUB FULLY CANCELED:", customerId)

        const { error } = await supabase
          .from("profiles")
          .update({
            is_pro: false,
            subscription_status: "canceled",
          })
          .eq("stripe_customer_id", customerId)

        if (error) {
          console.error("❌ CANCEL UPDATE FAILED:", error)
        } else {
          console.log("✅ USER DOWNGRADED")
        }
      } catch (err) {
        console.error("❌ customer.subscription.deleted crash:", err)
      }
    }

    // ⏭ EVERYTHING ELSE
    else {
      console.log("⏭ Ignored event:", event.type)
    }

    return new Response("OK", { status: 200 })

  } catch (err) {
    console.error("🔥 WEBHOOK CRASH:", err)
    return new Response("OK", { status: 200 })
  }
}