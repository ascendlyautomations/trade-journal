import Stripe from "stripe"
import { createClient } from "@supabase/supabase-js"
import { createServerClient } from "@supabase/ssr"
import { cookies } from "next/headers"

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY as string)

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function POST(req: Request) {
  try {
    console.log("🚀 /api/create-portal-session hit")

    const cookieStore = await cookies()
    const supabaseAuth = createServerClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      {
        cookies: {
          get: (name) => cookieStore.get(name)?.value,
        },
      }
    )
    const {
      data: { user: cookieUser },
    } = await supabaseAuth.auth.getUser()

    let user = cookieUser

    if (!user) {
      const authHeader = req.headers.get("authorization") || ""
      const bearer = authHeader.startsWith("Bearer ")
        ? authHeader.slice("Bearer ".length).trim()
        : ""

      if (bearer) {
        const { data: tokenData, error: tokenErr } = await supabase.auth.getUser(
          bearer
        )
        if (tokenErr) {
          console.log("❌ Bearer token auth failed for portal:", tokenErr.message)
        } else if (tokenData.user) {
          user = tokenData.user
        }
      }
    }

    if (!user) {
      console.log(
        "❌ Unauthorized portal attempt: no Supabase auth user in request cookies or bearer token"
      )
      return Response.json({ error: "Unauthorized" }, { status: 401 })
    }

    const { data: profile, error } = await supabase
      .from("profiles")
      .select("id, stripe_customer_id")
      .eq("id", user.id)
      .maybeSingle()

    if (error) {
      console.error("ERROR:", JSON.stringify(error, null, 2))
      return Response.json({ error: "Profile lookup failed" }, { status: 500 })
    }

    if (!profile?.id) {
      return Response.json({ error: "Profile not found" }, { status: 404 })
    }

    if (!profile.stripe_customer_id) {
      console.log("❌ No stripe_customer_id on profile for portal:", user.id)
      return Response.json(
        { error: "No Stripe customer on file" },
        { status: 400 }
      )
    }

    const baseUrl =
      process.env.NEXT_PUBLIC_BASE_URL?.trim() || new URL(req.url).origin

    const session = await stripe.billingPortal.sessions.create({
      customer: profile.stripe_customer_id,
      return_url: `${baseUrl}/settings?portal=return#subscription`,
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

