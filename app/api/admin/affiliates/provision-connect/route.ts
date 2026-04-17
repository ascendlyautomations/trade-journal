import { supabaseServiceRole, getRouteUser } from "@/app/api/_lib/getRouteUser"
import { ensureStripeConnectAccountForUser } from "@/lib/stripeConnectAffiliateServer"

export const runtime = "nodejs"

export async function POST(req: Request) {
  try {
    const user = await getRouteUser(req)
    if (!user?.id) {
      return Response.json({ error: "Unauthorized" }, { status: 401 })
    }

    const { data: adminRow } = await supabaseServiceRole
      .from("admin_users")
      .select("user_id")
      .eq("user_id", user.id)
      .maybeSingle()

    if (!adminRow?.user_id) {
      return Response.json({ error: "Forbidden" }, { status: 403 })
    }

    let body: { affiliateUserId?: string }
    try {
      body = (await req.json()) as { affiliateUserId?: string }
    } catch {
      return Response.json({ error: "Invalid JSON" }, { status: 400 })
    }

    const affiliateUserId = body.affiliateUserId?.trim()
    if (!affiliateUserId) {
      return Response.json({ error: "affiliateUserId required" }, { status: 400 })
    }

    if (!process.env.STRIPE_SECRET_KEY) {
      return Response.json({ error: "Stripe is not configured (STRIPE_SECRET_KEY)" }, { status: 503 })
    }

    const result = await ensureStripeConnectAccountForUser(supabaseServiceRole, affiliateUserId)

    if (!result.ok) {
      return Response.json({ error: result.error }, { status: result.status })
    }

    return Response.json({
      ok: true,
      skipped: !result.created,
      stripe_connected_account_id: result.accountId,
    })
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : "Stripe error"
    console.error("[provision-connect]", e)
    return Response.json({ error: msg }, { status: 500 })
  }
}
