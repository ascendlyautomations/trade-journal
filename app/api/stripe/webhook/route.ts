import Stripe from "stripe"
import { createClient } from "@supabase/supabase-js"

export const runtime = "nodejs"

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY as string)

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
    // 🔥 CHECKOUT COMPLETED (MAIN LOGIC)
    // ======================================================
    if (event.type === "checkout.session.completed") {
      try {
        const session = event.data.object as Stripe.Checkout.Session

        console.log("🔥 CHECKOUT SESSION HIT")
        console.log("📦 FULL SESSION:", session)

        const userId = session.metadata?.userId
        const referralCode = session.metadata?.referralCode
        const customerId = session.customer as string

        console.log("🧠 USER ID:", userId)
        console.log("🧠 REF CODE:", referralCode)
        console.log("🧠 CUSTOMER:", customerId)

        if (!userId) {
          console.log("❌ No userId — skipping")
          return new Response("OK", { status: 200 })
        }

        // ✅ STEP 1: UPGRADE USER
        const { error: upgradeError } = await supabase
          .from("profiles")
          .update({
            is_pro: true,
            subscription_status: "active",
            stripe_customer_id: customerId,
          })
          .eq("id", userId)

        if (upgradeError) {
          console.error("❌ UPGRADE FAILED:", upgradeError)
        } else {
          console.log("✅ USER UPGRADED:", userId)
        }

        // ==================================================
        // 🔥 REFERRAL LOGIC
        // ==================================================
        if (referralCode) {
          const { data: affiliate, error: affiliateError } =
            await supabase
              .from("affiliates")
              .select("*")
              .eq("code", referralCode)
              .single()

          if (affiliateError || !affiliate) {
            console.log("❌ Affiliate not found", affiliateError)
          } else {
            // CHECK IF ALREADY EXISTS
            const { data: existing } = await supabase
              .from("referrals")
              .select("*")
              .eq("referred_user_id", userId)

            if (existing && existing.length > 0) {
              console.log("⏭ Referral already exists")
            } else {
              const amount = (session.amount_total || 0) / 100

              // INSERT REFERRAL
              await supabase.from("referrals").insert({
                referred_user_id: userId,
                affiliate_id: affiliate.id,
                revenue: amount,
              })

              console.log("🔥 Referral inserted")

              // UPDATE AFFILIATE STATS
              const { data: affiliateProfile } = await supabase
                .from("profiles")
                .select("*")
                .eq("id", affiliate.user_id)
                .single()

              if (affiliateProfile) {
                const newRevenue =
                  (affiliateProfile.referral_revenue || 0) + amount

                await supabase
                  .from("profiles")
                  .update({
                    referral_revenue: newRevenue,
                    referral_count:
                      (affiliateProfile.referral_count || 0) + 1,
                  })
                  .eq("id", affiliate.user_id)

                console.log("💰 Affiliate updated:", newRevenue)
              }
            }
          }
        } else {
          console.log("⏭ No referral code")
        }
      } catch (err) {
        console.error("❌ checkout.session.completed crash:", err)
      }
    }

    // ======================================================
    // ❌ SUBSCRIPTION CANCELED
    // ======================================================
    else if (event.type === "customer.subscription.deleted") {
      try {
        const sub = event.data.object as Stripe.Subscription
        const customerId = sub.customer as string

        console.log("❌ SUB CANCELED:", customerId)

        await supabase
          .from("profiles")
          .update({
            is_pro: false,
            subscription_status: "canceled",
          })
          .eq("stripe_customer_id", customerId)
      } catch (err) {
        console.error("❌ cancel crash:", err)
      }
    }

    // ======================================================
    // ⏭ IGNORE EVERYTHING ELSE
    // ======================================================
    else {
      console.log("⏭ Ignored event:", event.type)
    }

    return new Response("OK", { status: 200 })
  } catch (err) {
    console.error("🔥 WEBHOOK CRASH:", err)
    return new Response("OK", { status: 200 })
  }
}