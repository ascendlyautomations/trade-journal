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

    const userId = body.userId as string | undefined

    console.log("🚀 RAW BODY:", body)

    if (!userId) {
      return Response.json({ error: "Missing userId" }, { status: 400 })
    }

    const { data: authUserData, error: authUserError } =
      await supabase.auth.admin.getUserById(userId)

    if (authUserError || !authUserData?.user) {
      console.error(
        "ERROR:",
        JSON.stringify(authUserError ?? { message: "No user" }, null, 2)
      )
      return Response.json({ error: "Invalid user" }, { status: 401 })
    }

    const user = authUserData.user
    const userEmail = user.email ?? undefined

    console.log("👤 Checkout for user:", user.id, userEmail)

    const { data: initialProfile, error: profileError } = await supabase
      .from("profiles")
      .select("id, stripe_customer_id")
      .eq("id", user.id)
      .maybeSingle()

    if (profileError) {
      console.error("ERROR:", JSON.stringify(profileError, null, 2))
      return Response.json(
        { error: "Could not load profile" },
        { status: 500 }
      )
    }

    let profile = initialProfile

    if (!profile) {
      const { error: ensureErr } = await supabase.from("profiles").upsert(
        {
          id: user.id,
          username: userEmail?.split("@")[0] || `user_${user.id.slice(0, 6)}`,
          name: "",
          is_pro: false,
          subscription_status: "inactive",
          created_at: new Date().toISOString(),
        },
        { onConflict: "id" }
      )

      if (ensureErr) {
        console.error("ERROR:", JSON.stringify(ensureErr, null, 2))
        return Response.json(
          { error: "Could not create profile" },
          { status: 500 }
        )
      }

      const refetch = await supabase
        .from("profiles")
        .select("id, stripe_customer_id")
        .eq("id", user.id)
        .maybeSingle()

      profile = refetch.data
      if (refetch.error) {
        console.error("ERROR:", JSON.stringify(refetch.error, null, 2))
        return Response.json(
          { error: "Could not load profile" },
          { status: 500 }
        )
      }
    }

    let customerId = profile?.stripe_customer_id as string | null | undefined

    if (!customerId) {
      console.log("🆕 Creating Stripe customer (no stripe_customer_id on profile)")

      try {
        const customer = await stripe.customers.create({
          email: userEmail,
          metadata: {
            user_id: user.id,
          },
        })

        customerId = customer.id

        const { error: updateErr } = await supabase
          .from("profiles")
          .update({ stripe_customer_id: customerId })
          .eq("id", user.id)

        if (updateErr) {
          console.error("ERROR:", JSON.stringify(updateErr, null, 2))
        } else {
          console.log("✅ Saved stripe_customer_id to profile:", customerId)
        }
      } catch (stripeErr) {
        console.error(
          "ERROR:",
          JSON.stringify(
            stripeErr instanceof Error
              ? { message: stripeErr.message, name: stripeErr.name }
              : stripeErr,
            null,
            2
          )
        )
        return Response.json(
          { error: "Could not create Stripe customer" },
          { status: 500 }
        )
      }
    } else {
      console.log("♻️ Reusing existing Stripe customer:", customerId)
    }

    if (!customerId) {
      console.error("ERROR:", JSON.stringify({ message: "Missing customer id" }, null, 2))
      return Response.json(
        { error: "Stripe customer unavailable" },
        { status: 500 }
      )
    }

    const PRICE_ID = "price_1TGugNQlLqJe3Tfgwg2q1ApV"

    const sessionConfig: Stripe.Checkout.SessionCreateParams = {
      mode: "subscription",
      customer: customerId,
      payment_method_types: ["card"],
      allow_promotion_codes: true,
      line_items: [
        {
          price: PRICE_ID,
          quantity: 1,
        },
      ],
      success_url: "http://localhost:3000/dashboard",
      cancel_url: "http://localhost:3000",
      metadata: {
        user_id: user.id,
        userId: user.id,
      },
      subscription_data: {
        metadata: {
          user_id: user.id,
          userId: user.id,
        },
      },
    }

    const session = await stripe.checkout.sessions.create(sessionConfig)

    console.log("🔥 SESSION CREATED:", session.id, session.metadata)

    return Response.json({ url: session.url })
  } catch (err: unknown) {
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
    const message = err instanceof Error ? err.message : "Stripe failed"
    return Response.json({ error: message }, { status: 500 })
  }
}
