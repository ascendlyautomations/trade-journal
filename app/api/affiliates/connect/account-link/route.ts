import { supabaseServiceRole, getRouteUser } from "@/app/api/_lib/getRouteUser"
import { ensureStripeConnectAccountForUser } from "@/lib/stripeConnectAffiliateServer"
import { getStripeServer, resolveAppUrl } from "@/lib/stripeServer"

export const runtime = "nodejs"

export async function POST(req: Request) {
  const isDev = process.env.NODE_ENV === "development"
  const authHeader = req.headers.get("authorization") ?? ""
  const hasBearer =
    authHeader.startsWith("Bearer ") && authHeader.slice("Bearer ".length).trim().length > 0

  try {
    const user = await getRouteUser(req)

    if (isDev) {
      console.log("[account-link] auth probe", {
        authUserId: user?.id ?? null,
        hasBearerToken: hasBearer,
        userResolved: Boolean(user?.id),
      })
    }

    if (!user?.id) {
      if (isDev) {
        console.log("[account-link] unauthorized", {
          reason: hasBearer
            ? "bearer_token_missing_invalid_or_expired"
            : "no_session_cookie_and_no_bearer",
        })
      }
      return Response.json({ error: "Unauthorized" }, { status: 401 })
    }

    const { data: affiliateRow, error: affiliateSelectErr } = await supabaseServiceRole
      .from("affiliates")
      .select("id")
      .eq("user_id", user.id)
      .maybeSingle()

    if (isDev) {
      console.log("[account-link] affiliate row", {
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
      return Response.json({ error: "Stripe is not configured" }, { status: 503 })
    }

    const ensured = await ensureStripeConnectAccountForUser(supabaseServiceRole, user.id)
    if (!ensured.ok) {
      return Response.json({ error: ensured.error }, { status: ensured.status })
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
    const msg = e instanceof Error ? e.message : "Stripe error"
    console.error("[account-link]", e)
    return Response.json({ error: msg }, { status: 500 })
  }
}
