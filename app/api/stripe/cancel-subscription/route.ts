import Stripe from "stripe"
import { createClient } from "@supabase/supabase-js"

export const runtime = "nodejs"

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY as string)

const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function POST(req: Request) {
  try {
    const authHeader = req.headers.get("authorization")
    const token = authHeader?.startsWith("Bearer ")
      ? authHeader.slice(7).trim()
      : null

    if (!token) {
      return Response.json({ error: "Unauthorized" }, { status: 401 })
    }

    const supabaseAuth = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      {
        global: {
          headers: { Authorization: `Bearer ${token}` },
        },
      }
    )

    const {
      data: { user },
      error: userErr,
    } = await supabaseAuth.auth.getUser()

    if (userErr || !user) {
      return Response.json({ error: "Unauthorized" }, { status: 401 })
    }

    let body: { userId?: string }
    try {
      body = await req.json()
    } catch {
      body = {}
    }

    if (!body.userId || body.userId !== user.id) {
      return Response.json({ error: "Invalid user" }, { status: 403 })
    }

    const { data: profile, error: profErr } = await supabaseAdmin
      .from("profiles")
      .select("id, stripe_customer_id")
      .eq("id", user.id)
      .maybeSingle()

    if (profErr || !profile?.id) {
      return Response.json({ error: "Profile not found" }, { status: 404 })
    }

    const customerId = profile.stripe_customer_id as string | null | undefined
    if (!customerId) {
      return Response.json(
        { error: "No Stripe customer on file" },
        { status: 400 }
      )
    }

    const active = await stripe.subscriptions.list({
      customer: customerId,
      status: "active",
      limit: 20,
    })

    const trialing = await stripe.subscriptions.list({
      customer: customerId,
      status: "trialing",
      limit: 20,
    })

    const subs = [...active.data, ...trialing.data].filter(
      (s) => !s.cancel_at_period_end
    )

    if (subs.length === 0) {
      return Response.json({
        ok: true,
        message: "No active subscription to cancel, or already set to cancel at period end.",
        canceled: 0,
      })
    }

    for (const sub of subs) {
      await stripe.subscriptions.update(sub.id, { cancel_at_period_end: true })
    }

    return Response.json({
      ok: true,
      canceled: subs.length,
      message: "Subscription will end after the current billing period.",
    })
  } catch (err) {
    console.error(
      "cancel-subscription:",
      err instanceof Error ? err.message : err
    )
    return Response.json({ error: "Failed to cancel subscription" }, { status: 500 })
  }
}
