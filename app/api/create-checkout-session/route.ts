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

    const userId = body?.userId
    const promoCode = body?.promoCode

    if (!userId) {
      return Response.json(
        { error: "Missing userId" },
        { status: 400 }
      )
    }

    console.log("Referral code received:", promoCode)

    if (promoCode) {
      const { data: affiliate } = await supabase
        .from("affiliates")
        .select("*")
        .eq("code", promoCode)
        .single()

      console.log("Affiliate found:", affiliate)

      if (affiliate) {
        await supabase.from("referrals").insert({
          referred_user_id: userId,
          affiliate_id: affiliate.id,
          code: promoCode
        })
      }
    }

    // 🔥 BUILD DISCOUNTS PROPERLY
    let discounts = []

    if (promoCode) {
      discounts = [
        {
          promotion_code: promoCode,
        },
      ]
    }

    const PRICE_ID = "price_1TGugNQlLqJe3Tfgwg2q1ApV"

    const session = await stripe.checkout.sessions.create({
      mode: "subscription",

      allow_promotion_codes: true, // ✅ Stripe input box


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
        userId,
      },
    })

    return Response.json({ url: session.url })
  } catch (err: any) {
    console.error("🔥 STRIPE ERROR:", err)

    return Response.json(
      { error: err?.message || "Stripe failed" },
      { status: 500 }
    )
  }
}