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
    const { userId, referralCode } = await req.json()

    if (!userId && !referralCode) {
      return Response.json(
        { error: "Missing userId or referralCode" },
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
      metadata: {
        userId: userId || "",
        referralCode: referralCode || "",
      },
    }

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

    const session = await stripe.checkout.sessions.create(sessionConfig)

    return Response.json({ url: session.url })
  } catch (err: any) {
    console.error("🔥 STRIPE ERROR:", err)

    return Response.json(
      { error: err?.message || "Stripe failed" },
      { status: 500 }
    )
  }
}