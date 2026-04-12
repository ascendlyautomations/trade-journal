import Stripe from "stripe"
import { createClient } from "@supabase/supabase-js"

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY as string)

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function POST(req: Request) {
  try {
    const { userId } = await req.json()

    if (!userId) {
      return Response.json({ error: "Missing userId" }, { status: 400 })
    }

    const { data: profile, error } = await supabase
      .from("profiles")
      .select("id, stripe_customer_id")
      .eq("id", userId)
      .maybeSingle()

    if (error) {
      console.error("ERROR:", JSON.stringify(error, null, 2))
      return Response.json({ error: "Profile lookup failed" }, { status: 500 })
    }

    if (!profile?.id) {
      return Response.json({ error: "Profile not found" }, { status: 404 })
    }

    if (!profile.stripe_customer_id) {
      return Response.json(
        { error: "No Stripe customer on file" },
        { status: 400 }
      )
    }

    const session = await stripe.billingPortal.sessions.create({
      customer: profile.stripe_customer_id,
      return_url: "http://localhost:3000/settings"
    })

    return Response.json({ url: session.url })
  } catch (err) {
    console.error(
      "ERROR:",
      JSON.stringify(
        err instanceof Error
          ? { message: err.message, name: err.name }
          : err,
        null,
        2
      )
    )
    return Response.json({ error: "Portal failed" }, { status: 500 })
  }
}

