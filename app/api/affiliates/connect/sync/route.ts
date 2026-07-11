import { supabaseServiceRole, getRouteUser } from "@/app/api/_lib/getRouteUser"
import {
  AFFILIATE_CONNECT_SELECT,
  parseAffiliateConnectRow,
  stripeAccountToAffiliateConnectPatch,
} from "@/lib/affiliateStripeConnect"
import { getStripeServer } from "@/lib/stripeServer"
import { devLog } from "@/lib/devLog"
import { jsonUserFacingError, USER_FACING_ERROR_MESSAGES } from "@/lib/userFacingError"

export const runtime = "nodejs"

/**
 * Affiliate-only: syncs Stripe Connect status for `affiliates.user_id === auth user`.
 * Requires session via cookies or `Authorization: Bearer` (browser client uses Bearer).
 */
export async function POST(req: Request) {
  const isDev = process.env.NODE_ENV === "development"
  const authHeader = req.headers.get("authorization") ?? ""
  const hasBearer =
    authHeader.startsWith("Bearer ") && authHeader.slice("Bearer ".length).trim().length > 0

  try {
    const user = await getRouteUser(req)

    if (isDev) {
      devLog("[connect/sync] auth probe", {
        authUserId: user?.id ?? null,
        hasBearerToken: hasBearer,
        userResolved: Boolean(user?.id),
      })
    }

    if (!user?.id) {
      if (isDev) {
        devLog("[connect/sync] unauthorized", {
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

    let stripe: ReturnType<typeof getStripeServer>
    try {
      stripe = getStripeServer()
    } catch {
      return Response.json(
        {
          error: USER_FACING_ERROR_MESSAGES.BILLING_UNAVAILABLE,
          skipped: true,
        },
        { status: 503 }
      )
    }

    const { data: affiliate, error: affErr } = await supabaseServiceRole
      .from("affiliates")
      .select("id, stripe_connected_account_id")
      .eq("user_id", user.id)
      .maybeSingle()

    if (affErr) {
      if (isDev) console.error("[connect/sync] affiliate select", affErr)
      return Response.json({ error: "Could not load affiliate row" }, { status: 500 })
    }

    if (!affiliate?.id) {
      if (isDev) {
        devLog("[connect/sync] denied", {
          reason: "no_affiliate_row",
          authUserId: user.id,
        })
      }
      return Response.json(
        { ok: false, error: "No affiliate record for this account." },
        { status: 403 }
      )
    }

    const acctId =
      affiliate.stripe_connected_account_id != null
        ? String(affiliate.stripe_connected_account_id).trim()
        : ""

    if (isDev) {
      devLog("[connect/sync] affiliate row", {
        authUserId: user.id,
        affiliateRowFound: true,
        stripe_connected_account_id: acctId || null,
      })
    }

    if (!acctId) {
      return Response.json({ ok: true, skipped: true, affiliate: null })
    }

    const account = await stripe.accounts.retrieve(acctId)
    if (isDev) {
      devLog("[connect/sync] stripe.accounts.retrieve ok", {
        stripeAccountId: account.id,
        details_submitted: account.details_submitted,
        payouts_enabled: account.payouts_enabled,
      })
    }

    const patch = stripeAccountToAffiliateConnectPatch(account)

    await supabaseServiceRole.from("affiliates").update(patch).eq("user_id", user.id)

    const { data: row } = await supabaseServiceRole
      .from("affiliates")
      .select(AFFILIATE_CONNECT_SELECT)
      .eq("user_id", user.id)
      .maybeSingle()

    if (!row || typeof row !== "object") {
      return Response.json({ ok: true, affiliate: null })
    }

    return Response.json({
      ok: true,
      skipped: false,
      affiliate: parseAffiliateConnectRow(row as Record<string, unknown>),
    })
  } catch (e: unknown) {
    return jsonUserFacingError(e, 500, "connect/sync")
  }
}
