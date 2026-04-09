import Stripe from "stripe"
import { createClient } from "@supabase/supabase-js"

export const runtime = "nodejs"

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY as string)

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

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
    // ✅ CHECKOUT COMPLETE → UPGRADE USER + METADATA REFERRAL
    // ======================================================
    if (event.type === "checkout.session.completed") {
      try {
        const session = event.data.object as Stripe.Checkout.Session

        const userId = session.metadata?.userId
        const referralCode = session.metadata?.referralCode
        const customerId = session.customer as string

        console.log("🎯 REFERRAL CODE:", referralCode)

        // ✅ Upgrade user
        if (userId) {
          await supabase
            .from("profiles")
            .update({
              is_pro: true,
              stripe_customer_id: customerId,
            })
            .eq("id", userId)

          console.log("✅ USER UPGRADED:", userId)
        }

        // ✅ Handle referral
        if (referralCode) {
          const { data: referrer, error } = await supabase
            .from("profiles")
            .select("*")
            .eq("referral_code", referralCode)
            .single()

          console.log("👀 REFERRER LOOKUP:", referrer, error)

          if (referrer) {
            const { error: updateError } = await supabase
              .from("profiles")
              .update({
                referral_count:
                  Number(referrer.referral_count || 0) + 1,
              })
              .eq("id", referrer.id)

            if (updateError) {
              console.log("❌ UPDATE FAILED:", updateError)
            } else {
              console.log("✅ REFERRAL COUNT UPDATED")
            }
          } else {
            console.log("❌ NO REFERRER FOUND")
          }
        }
      } catch (err) {
        console.error("❌ checkout.session.completed crash:", err)
      }
    }

    // ======================================================
    // ❌ SUB CANCEL
    // ======================================================
    if (event.type === "customer.subscription.deleted") {
      try {
        const sub = event.data.object as Stripe.Subscription

        await supabase
          .from("profiles")
          .update({
            is_pro: false,
            subscription_status: "canceled",
          })
          .eq("stripe_customer_id", sub.customer as string)

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