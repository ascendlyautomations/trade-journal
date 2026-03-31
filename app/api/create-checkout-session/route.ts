import Stripe from "stripe"

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY as string)

export async function POST(req: Request) {
  try {
    const body = await req.json()
    const userId = body?.userId

    if (!userId) {
      return Response.json(
        { error: "Missing userId" },
        { status: 400 }
      )
    }

    // ✅ YOUR REAL PRICE ID
    const PRICE_ID = "price_1TGugNQlLqJe3Tfgwg2q1ApV"

    const session = await stripe.checkout.sessions.create({
      mode: "subscription",

      payment_method_types: ["card"],

      line_items: [
        {
          price: PRICE_ID,
          quantity: 1,
        },
      ],

      subscription_data: {
        trial_period_days: 14,
      },

      success_url: "http://localhost:3000/dashboard",
      cancel_url: "http://localhost:3000",

      // 🔥 THIS FIXES YOUR BLANK SCREEN
      customer_email: "test@example.com",

      metadata: {
        userId,
      },
    })

    return Response.json({ url: session.url })
  } catch (err: any) {
    console.error("🔥 STRIPE ERROR:", err)

    return Response.json(
      {
        error: err?.message || "Stripe failed",
      },
      { status: 500 }
    )
  }
}