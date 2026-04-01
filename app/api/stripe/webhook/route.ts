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
    // ✅ CHECKOUT COMPLETE → ONLY UPGRADE USER
    // ======================================================
    if (event.type === "checkout.session.completed") {
      try {
        const session = event.data.object as Stripe.Checkout.Session

        const userId = session.metadata?.userId
        const customerId = session.customer as string

        if (!userId) return new Response("OK", { status: 200 })

        await supabase
          .from("profiles")
          .update({
            is_pro: true,
            stripe_customer_id: customerId,
          })
          .eq("id", userId)

        console.log("✅ USER UPGRADED:", userId)

      } catch (err) {
        console.error("❌ checkout.session.completed crash:", err)
      }
    }

    // ======================================================
    // 💰 REAL PAYMENT → HANDLE REFERRALS HERE
    // ======================================================
    else if (event.type === "invoice.payment_succeeded") {
      try {
        const invoice = event.data.object as Stripe.Invoice

        const customerId = invoice.customer as string
        const amount = Number((invoice.amount_paid || 0) / 100)

        console.log("💰 PAYMENT SUCCESS:", amount)

        // 🔍 Get user by stripe_customer_id
        const { data: user } = await supabase
          .from("profiles")
          .select("*")
          .eq("stripe_customer_id", customerId)
          .single()

        if (!user) {
          console.log("❌ No user found for customer")
          return new Response("OK", { status: 200 })
        }

        const userId = user.id

        // 🔍 Get referral code from affiliates via referrals table OR metadata fallback
        const { data: existingReferral } = await supabase
          .from("referrals")
          .select("*")
          .eq("referred_user_id", userId)

        // ==================================================
        // 🆕 FIRST TIME PAYMENT → CREATE REFERRAL
        // ==================================================
        if (!existingReferral || existingReferral.length === 0) {
          console.log("🆕 FIRST PAYMENT → creating referral")

          // ⚠️ IMPORTANT: we need referralCode stored earlier
          const referralCode = user.referral_code_used

          if (!referralCode) {
            console.log("⏭ No referral code stored")
            return new Response("OK", { status: 200 })
          }

          const { data: affiliate } = await supabase
            .from("affiliates")
            .select("*")
            .eq("code", referralCode)
            .single()

          if (!affiliate) {
            console.log("❌ Affiliate not found")
            return new Response("OK", { status: 200 })
          }

          // 🆕 INSERT REFERRAL
          await supabase.from("referrals").insert({
            referred_user_id: userId,
            affiliate_id: affiliate.id,
            revenue: amount,
          })

          // ✅ UPDATE AFFILIATE STATS (COUNT ONLY ONCE)
          const { data: affiliateProfile } = await supabase
            .from("profiles")
            .select("*")
            .eq("id", affiliate.user_id)
            .single()

          if (affiliateProfile) {
            await supabase
              .from("profiles")
              .update({
                referral_count:
                  Number(affiliateProfile.referral_count || 0) + 1,
                referral_revenue:
                  Number(affiliateProfile.referral_revenue || 0) + amount,
              })
              .eq("id", affiliate.user_id)
          }

        } else {
          // ==================================================
          // 🔁 RECURRING PAYMENT → ONLY ADD REVENUE
          // ==================================================
          console.log("🔁 RECURRING PAYMENT → updating revenue")

          const referral = existingReferral[0]

          const newRevenue =
            Number(referral.revenue || 0) + amount

          await supabase
            .from("referrals")
            .update({
              revenue: newRevenue,
            })
            .eq("id", referral.id)

          // update affiliate revenue ONLY
          const { data: affiliateProfile } = await supabase
            .from("profiles")
            .select("*")
            .eq("id", referral.affiliate_id)
            .single()

          if (affiliateProfile) {
            await supabase
              .from("profiles")
              .update({
                referral_revenue:
                  Number(affiliateProfile.referral_revenue || 0) + amount,
              })
              .eq("id", referral.affiliate_id)
          }
        }

      } catch (err) {
        console.error("❌ payment crash:", err)
      }
    }

    // ======================================================
    // ❌ SUB CANCELED
    // ======================================================
    else if (event.type === "customer.subscription.deleted") {
      try {
        const sub = event.data.object as Stripe.Subscription
        const customerId = sub.customer as string

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

    return new Response("OK", { status: 200 })

  } catch (err) {
    console.error("🔥 WEBHOOK CRASH:", err)
    return new Response("OK", { status: 200 })
  }
}