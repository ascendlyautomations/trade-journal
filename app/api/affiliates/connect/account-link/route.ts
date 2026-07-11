import { supabaseServiceRole, getRouteUser } from "@/app/api/_lib/getRouteUser"
import { ensureStripeConnectAccountForUser } from "@/lib/stripeConnectAffiliateServer"
import { getStripeServer, resolveAppUrl } from "@/lib/stripeServer"
import { devLog } from "@/lib/devLog"
import {
  jsonUserFacingError,
  toUserFacingErrorMessage,
  USER_FACING_ERROR_MESSAGES,
} from "@/lib/userFacingError"

export const runtime = "nodejs"

export async function POST(req: Request) {
  const isDev = process.env.NODE_ENV === "development"
  const authHeader = req.headers.get("authorization") ?? ""
  const hasBearer =
    authHeader.startsWith("Bearer ") && authHeader.slice("Bearer ".length).trim().length > 0

  try {
    const user = await getRouteUser(req)

    if (isDev) {
      devLog("[account-link] auth probe", {
        authUserId: user?.id ?? null,
        hasBearerToken: hasBearer,
        userResolved: Boolean(user?.id),
      })
    }

    if (!user?.id) {
      if (isDev) {
        devLog("[account-link] unauthorized", {
          reason: hasBearer
            ? "bearer_token_missing_invalid_or_expired"
            : "no_session_cookie_and_no_bearer",
        })
      }
      return Response.json(
        { error: USER_FACING_ERROR_MESSAGES.SESSION_EXPIRED },
        { status: 401 }
      )
    }

    const { data: affiliateRow, error: affiliateSelectErr } = await supabaseServiceRole
      .from("affiliates")
      .select("id")
      .eq("user_id", user.id)
      .maybeSingle()

    if (isDev) {
      devLog("[account-link] affiliate row", {
        found: Boolean(affiliateRow?.id),
        selectError: affiliateSelectErr?.message ?? null,
      })
    }

    if (affiliateSelectErr || !affiliateRow?.id) {
      return Response.json(
        {
          error:
            "No affiliate record for this account. Finish approval first, then try payout setup again.",
        },
        { status: 403 }
      )
    }

    let stripe: ReturnType<typeof getStripeServer>
    try {
      stripe = getStripeServer()
    } catch {
      return Response.json(
        { error: USER_FACING_ERROR_MESSAGES.BILLING_UNAVAILABLE },
        { status: 503 }
      )
    }

    const ensured = await ensureStripeConnectAccountForUser(supabaseServiceRole, user.id)
    if (!ensured.ok) {
      return Response.json(
        {
          error: toUserFacingErrorMessage(
            ensured.error,
            USER_FACING_ERROR_MESSAGES.BILLING_UNAVAILABLE
          ),
        },
        { status: ensured.status }
      )
    }

    const base = resolveAppUrl(req)
    const accountId = ensured.accountId

    const link = await stripe.accountLinks.create({
      account: accountId,
      refresh_url: `${base}/affiliate/payout-setup/refresh`,
      return_url: `${base}/affiliate/payout-setup/return`,
      type: "account_onboarding",
    })

    await supabaseServiceRole
      .from("affiliates")
      .update({
        stripe_onboarding_last_url: link.url,
        stripe_onboarding_updated_at: new Date().toISOString(),
      })
      .eq("user_id", user.id)

    return Response.json({ ok: true, url: link.url })
  } catch (e: unknown) {
    return jsonUserFacingError(
      e,
      500,
      "account-link",
    )
  }
}
