import { supabaseServiceRole, getRouteUser } from "@/app/api/_lib/getRouteUser"
import { ensureStripeConnectAccountForUser } from "@/lib/stripeConnectAffiliateServer"
import { jsonUserFacingError, toUserFacingErrorMessage, USER_FACING_ERROR_MESSAGES } from "@/lib/userFacingError"

export const runtime = "nodejs"

export async function POST(req: Request) {
  try {
    const user = await getRouteUser(req)
    if (!user?.id) {
      return Response.json(
        { error: USER_FACING_ERROR_MESSAGES.SESSION_EXPIRED },
        { status: 401 }
      )
    }

    const { data: adminRow } = await supabaseServiceRole
      .from("admin_users")
      .select("user_id")
      .eq("user_id", user.id)
      .maybeSingle()

    if (!adminRow?.user_id) {
      return Response.json(
        { error: USER_FACING_ERROR_MESSAGES.UNAUTHORIZED },
        { status: 403 }
      )
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
      return Response.json(
        { error: USER_FACING_ERROR_MESSAGES.BILLING_UNAVAILABLE },
        { status: 503 }
      )
    }

    const result = await ensureStripeConnectAccountForUser(supabaseServiceRole, affiliateUserId)

    if (!result.ok) {
      return Response.json(
        {
          error: toUserFacingErrorMessage(
            result.error,
            USER_FACING_ERROR_MESSAGES.BILLING_UNAVAILABLE
          ),
        },
        { status: result.status }
      )
    }

    return Response.json({
      ok: true,
      skipped: !result.created,
      stripe_connected_account_id: result.accountId,
    })
  } catch (e: unknown) {
    return jsonUserFacingError(e, 500, "provision-connect")
  }
}
