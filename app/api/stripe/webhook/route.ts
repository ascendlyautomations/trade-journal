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

    // ✅ CHECKOUT COMPLETED (attach customer ID)
    if (event.type === "checkout.session.completed") {
      const session = event.data.object as Stripe.Checkout.Session
      const userId = session.metadata?.userId

      if (!userId) {
        console.error("❌ No userId in metadata")
        return new Response("Missing userId", { status: 400 })
      }

      const { error } = await supabase
        .from("profiles")
        .update({
          stripe_customer_id: session.customer as string,
        })
        .eq("id", userId)

      if (error) {
        console.error("❌ ERROR saving customer ID:", error)
      } else {
        console.log("✅ Customer ID saved")
      }
    }

    // 💰 INVOICE PAID (main trigger for PRO)
    else if (event.type === "invoice.paid") {
      const invoice = event.data.object as Stripe.Invoice
      const customerId = invoice.customer as string

      const { data: user, error: fetchError } = await supabase
        .from("profiles")
        .select("*")
        .eq("stripe_customer_id", customerId)
        .single()

      if (fetchError || !user) {
        console.error("❌ USER NOT FOUND:", customerId)
        return new Response("User not found", { status: 400 })
      }

      if (user.referred_by) {
        const { data: refUser } = await supabase
          .from("profiles")
          .select("*")
          .eq("id", user.referred_by)
          .single()

        if (refUser) {
          await supabase
            .from("profiles")
            .update({
              referral_earnings: (refUser.referral_earnings || 0) + 10,
              referral_count: (refUser.referral_count || 0) + 1
            })
            .eq("id", refUser.id)
        }
      }

      const { error: updateError } = await supabase
        .from("profiles")
        .update({
          is_pro: true,
          subscription_status: "active",
        })
        .eq("id", user.id)

      if (updateError) {
        console.error("❌ UPDATE FAILED:", updateError)
      } else {
        console.log("🔥 USER UPGRADED TO PRO")
      }
    }

    // 🔁 SUBSCRIPTION UPDATED (cancel scheduled / resumed)
    else if (event.type === "customer.subscription.updated") {
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
        return new Response("User not found", { status: 400 })
      }

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

    // ❌ FULLY CANCELED (end of billing period)
    else if (event.type === "customer.subscription.deleted") {
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
    }

    // ⏭ EVERYTHING ELSE
    else {
      console.log("⏭ Ignored event:", event.type)
    }

    return new Response("OK", { status: 200 })

  } catch (err) {
    console.error("🔥 WEBHOOK CRASH:", err)
    return new Response("Server error", { status: 500 })
  }
}