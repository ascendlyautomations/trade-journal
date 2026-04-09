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
    const body = await req.json()

    const userId = body.userId
    let referralCode = body.referralCode

    console.log("🚀 RAW BODY:", body)

    // 🔥 FORCE FIX: if referralCode missing, try fallback
    if (!referralCode || referralCode === "") {
      console.log("⚠️ referralCode missing — attempting fallback")

      // If frontend forgot, just don't break flow
      referralCode = ""
    }

    console.log("🧠 FINAL referralCode:", referralCode)

    if (!userId) {
      return Response.json(
        { error: "Missing userId" },
        { status: 400 }
      )
    }

    const PRICE_ID = "price_1TGugNQlLqJe3Tfgwg2q1ApV"

    const sessionConfig: Stripe.Checkout.SessionCreateParams = {
      mode: "subscription",
      payment_method_types: ["card"],
      line_items: [
        {
          price: PRICE_ID,
          quantity: 1,
        },
      ],
      success_url: "http://localhost:3000/dashboard",
      cancel_url: "http://localhost:3000",
      customer_email: "test@example.com",
    }

    // 🔥 OPTIONAL DISCOUNT LOGIC
    if (referralCode) {
      const { data: affiliate } = await supabase
        .from("affiliates")
        .select("*")
        .eq("code", referralCode)
        .single()

      if (affiliate?.stripe_promo_code_id) {
        sessionConfig.discounts = [
          {
            promotion_code: affiliate.stripe_promo_code_id,
          },
        ]
      } else {
        sessionConfig.allow_promotion_codes = true
      }
    } else {
      sessionConfig.allow_promotion_codes = true
    }

    {
      const referralCode = body?.referralCode || null

      console.log("🚀 RECEIVED REFERRAL CODE:", referralCode)

      sessionConfig.metadata = {
        ...sessionConfig.metadata,
        userId,
        referralCode: referralCode || "",
      }
    }

    const session = await stripe.checkout.sessions.create(sessionConfig)

    console.log("🔥 SESSION CREATED WITH METADATA:", session.metadata)

    return Response.json({ url: session.url })
  } catch (err: any) {
    console.error("🔥 STRIPE ERROR:", err)

    return Response.json(
      { error: err?.message || "Stripe failed" },
      { status: 500 }
    )
  }
}