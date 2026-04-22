import Stripe from "stripe"
import { NextResponse } from "next/server"
import { createClient } from "@supabase/supabase-js"

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY as string)
const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function POST(req: Request) {
  const authHeader = req.headers.get("authorization")

  if (!authHeader) {
    return NextResponse.json({ error: "No auth header" }, { status: 401 })
  }

  const token = authHeader.replace("Bearer ", "")

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser(token)

  console.log("User:", user)

  if (!user || userError) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("stripe_customer_id")
    .eq("id", user.id)
    .single()

  // OPTIONAL: cancel Stripe subscription
  if (profile?.stripe_customer_id) {
    try {
      const subs = await stripe.subscriptions.list({
        customer: profile.stripe_customer_id,
        status: "all",
        limit: 1,
      })

      if (subs.data.length > 0) {
        await stripe.subscriptions.cancel(subs.data[0].id)
      }
    } catch (err) {
      console.error("Stripe cancel error:", err)
    }
  }

  // Delete profile
  await supabase.from("profiles").delete().eq("id", user.id)

  // Delete auth user
  const { error: deleteError } = await supabase.auth.admin.deleteUser(
    user.id
  )

  if (deleteError) {
    return NextResponse.json({ error: deleteError.message }, { status: 500 })
  }

  return NextResponse.json({ success: true })
}
