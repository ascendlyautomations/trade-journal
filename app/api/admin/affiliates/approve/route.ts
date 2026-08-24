import { supabaseServiceRole, getRouteUser } from "@/app/api/_lib/getRouteUser"
import { adminApproveAffiliateApplication } from "@/lib/affiliateAdmin"
import { createAffiliatePromotionCode } from "@/lib/affiliateStripeDiscount"
import { getStripeServer } from "@/lib/stripeServer"
import {
  jsonUserFacingError,
  toUserFacingErrorMessage,
  USER_FACING_ERROR_MESSAGES,
} from "@/lib/userFacingError"

export const runtime = "nodejs"

/**
 * Approve affiliate application and auto-provision a Stripe promotion code
 * against the shared 10%-off-once coupon (unless a promo ID is supplied).
 */
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

    if (!process.env.STRIPE_SECRET_KEY) {
      return Response.json(
        { error: USER_FACING_ERROR_MESSAGES.BILLING_UNAVAILABLE },
        { status: 503 }
      )
    }

    let body: {
      applicationId?: string
      adminCode?: string | null
      stripePromo?: string | null
    }
    try {
      body = (await req.json()) as typeof body
    } catch {
      return Response.json({ error: "Invalid JSON" }, { status: 400 })
    }

    const applicationId = body.applicationId?.trim()
    if (!applicationId) {
      return Response.json({ error: "applicationId required" }, { status: 400 })
    }

    const adminCode = body.adminCode?.trim() ? body.adminCode.trim() : null
    let stripePromo = body.stripePromo?.trim() ? body.stripePromo.trim() : null

    const { data: application, error: appErr } = await supabaseServiceRole
      .from("affiliate_applications")
      .select("id, user_id, requested_code, status")
      .eq("id", applicationId)
      .maybeSingle()

    if (appErr || !application) {
      return Response.json({ error: "Application not found" }, { status: 404 })
    }

    if (application.status !== "pending") {
      return Response.json(
        { error: "This application is no longer pending." },
        { status: 409 }
      )
    }

    const affiliateUserId = application.user_id
    if (!affiliateUserId) {
      return Response.json(
        { error: "Application is missing an applicant." },
        { status: 400 }
      )
    }

    const { data: profile } = await supabaseServiceRole
      .from("profiles")
      .select("username")
      .eq("id", affiliateUserId)
      .maybeSingle()

    const resolvedCode = (
      adminCode ||
      application.requested_code ||
      `${String(profile?.username || "AFF").slice(0, 8)}${Math.floor(
        100 + Math.random() * 900
      )}`
    )
      .trim()
      .toUpperCase()

    if (!stripePromo) {
      try {
        const stripe = getStripeServer()
        const promo = await createAffiliatePromotionCode({
          stripe,
          code: resolvedCode,
          affiliateUserId,
        })
        stripePromo = promo.id
      } catch (promoErr) {
        console.error("[admin/affiliates/approve] promo create failed:", promoErr)
        return Response.json(
          {
            error: toUserFacingErrorMessage(
              promoErr,
              "Could not create Stripe promotion code. Check the code is unique, then try again."
            ),
          },
          { status: 502 }
        )
      }
    }

    const { result, error } = await adminApproveAffiliateApplication(
      supabaseServiceRole,
      {
        applicationId,
        adminCode: adminCode || resolvedCode,
        stripePromo,
      }
    )

    if (error) {
      return Response.json({ error: error.message }, { status: 400 })
    }

    return Response.json({
      ok: true,
      result,
      stripe_promo_code_id: stripePromo,
      code: resolvedCode,
    })
  } catch (e: unknown) {
    return jsonUserFacingError(e, 500, "admin-affiliates-approve")
  }
}
