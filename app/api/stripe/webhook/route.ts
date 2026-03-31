import Stripe from "stripe"
import { headers } from "next/headers"
import { createClient } from "@supabase/supabase-js"

export const runtime = "nodejs"
console.log("ENV CHECK:", {
  hasUrl: !!process.env.NEXT_PUBLIC_SUPABASE_URL,
  hasServiceKey: !!process.env.SUPABASE_SERVICE_ROLE_KEY,
  hasWebhookSecret: !!process.env.STRIPE_WEBHOOK_SECRET,
})

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY as string, {
  apiVersion: "2024-06-20",
})

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function POST(req: Request) {
  console.log("🚀 Webhook endpoint hit")

  try {
    const body = await req.text()
    const sig = headers().get("stripe-signature")

    if (!sig) {
      console.error("❌ No stripe signature found")
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
      console.error("❌ Signature verification failed:", err)
      return new Response("Invalid signature", { status: 400 })
    }

    console.log("📩 Event type:", event.type)

    // 🔥 ONLY handle checkout success for now
    if (event.type === "checkout.session.completed") {
      const session = event.data.object as Stripe.Checkout.Session

      console.log("🔥 SESSION RECEIVED:", session.id)

      const userId = session.metadata?.userId

      if (!userId) {
        console.error("❌ No userId in metadata")
        return new Response("Missing userId", { status: 400 })
      }

      console.log("👤 Updating user:", userId)

      try {
        const { error } = await supabase
          .from("profiles")
          .update({
            is_pro: true,
            stripe_customer_id: session.customer as string,
            subscription_status: "active",
          })
          .eq("id", userId)

        if (error) {
          console.error("❌ Supabase error:", error)
        } else {
          console.log("✅ Supabase updated successfully")
        }
      } catch (dbErr) {
        console.error("❌ DB crash:", dbErr)
      }
    }

    return new Response("OK", { status: 200 })

  } catch (err) {
    console.error("🔥 WEBHOOK CRASHED:", err)
    return new Response("Server error", { status: 500 })
  }
}