import { supabaseServiceRole, getRouteUser } from "@/app/api/_lib/getRouteUser"
import { getStripeServer } from "@/lib/stripeServer"
import Stripe from "stripe"
import {
  jsonUserFacingError,
  toUserFacingErrorMessage,
  USER_FACING_ERROR_MESSAGES,
} from "@/lib/userFacingError"

export const runtime = "nodejs"

const CURRENCY = "usd"

function dollarsToPositiveCents(amount: number): { cents: number } | { error: string } {
  if (!Number.isFinite(amount) || amount <= 0) {
    return { error: "Invalid payout amount." }
  }
  const cents = Math.round(amount * 100)
  if (cents < 1) {
    return { error: "Amount must be at least $0.01." }
  }
  return { cents }
}

function stripeUserMessage(err: Stripe.errors.StripeError): string {
  const code = err.code
  if (code === "balance_insufficient") {
    return "Insufficient funds in the platform Stripe balance. Add funds or reduce the payout amount."
  }
  if (code === "account_invalid" || code === "invalid_request_error") {
    const msg = err.message?.toLowerCase() ?? ""
    if (msg.includes("destination") || msg.includes("connect")) {
      return "Connected account is not valid for transfers. Verify the affiliate completed Stripe onboarding."
    }
  }
  return toUserFacingErrorMessage(
    err,
    "The transfer could not be completed. Please try again."
  )
}

export async function POST(req: Request) {
  const isDev = process.env.NODE_ENV === "development"

  try {
    const adminUser = await getRouteUser(req)
    if (!adminUser?.id) {
      return Response.json(
        { error: USER_FACING_ERROR_MESSAGES.SESSION_EXPIRED },
        { status: 401 }
      )
    }

    const { data: adminRow } = await supabaseServiceRole
      .from("admin_users")
      .select("user_id")
      .eq("user_id", adminUser.id)
      .maybeSingle()

    if (!adminRow?.user_id) {
      return Response.json(
        { error: USER_FACING_ERROR_MESSAGES.UNAUTHORIZED },
        { status: 403 }
      )
    }

    let body: { payoutRequestId?: string; adminNotes?: string | null }
    try {
      body = (await req.json()) as { payoutRequestId?: string; adminNotes?: string | null }
    } catch {
      return Response.json({ error: "Invalid JSON" }, { status: 400 })
    }

    const payoutRequestId = body.payoutRequestId?.trim()
    if (!payoutRequestId) {
      return Response.json({ error: "payoutRequestId is required" }, { status: 400 })
    }

    const { data: pr, error: prErr } = await supabaseServiceRole
      .from("affiliate_payout_requests")
      .select(
        "id, user_id, affiliate_id, amount, status, admin_notes, payout_reference, stripe_transfer_id"
      )
      .eq("id", payoutRequestId)
      .maybeSingle()

    if (prErr) {
      if (isDev) console.error("[admin-payout-execute] load request", prErr)
      return Response.json({ error: "Could not load payout request" }, { status: 500 })
    }

    if (!pr) {
      return Response.json({ error: "Payout request not found." }, { status: 404 })
    }

    const row = pr as Record<string, unknown>
    const status = String(row.status ?? "")
    const stripeTransferExisting =
      row.stripe_transfer_id != null && String(row.stripe_transfer_id).trim().length > 0

    if (status === "paid" || stripeTransferExisting) {
      return Response.json(
        { error: "This payout was already marked paid or has a Stripe transfer recorded." },
        { status: 409 }
      )
    }

    if (status !== "approved") {
      return Response.json(
        { error: "Only approved payout requests can be paid. Approve it first." },
        { status: 400 }
      )
    }

    const userId = String(row.user_id ?? "")
    const affiliateId = row.affiliate_id != null ? String(row.affiliate_id) : ""

    if (!affiliateId) {
      return Response.json(
        { error: "Payout request is missing affiliate_id; cannot transfer." },
        { status: 400 }
      )
    }

    const amountNum = Number(row.amount)
    const centsResult = dollarsToPositiveCents(amountNum)
    if ("error" in centsResult) {
      return Response.json({ error: centsResult.error }, { status: 400 })
    }
    const { cents } = centsResult

    const { data: affiliate, error: affErr } = await supabaseServiceRole
      .from("affiliates")
      .select("id, user_id, stripe_connected_account_id, stripe_payouts_enabled, stripe_onboarding_complete")
      .eq("id", affiliateId)
      .maybeSingle()

    if (affErr || !affiliate) {
      if (isDev) console.error("[admin-payout-execute] load affiliate", affErr)
      return Response.json({ error: "Affiliate record not found for this payout." }, { status: 400 })
    }

    const acct = affiliate as Record<string, unknown>
    const affUserId = String(acct.user_id ?? "")
    if (affUserId && userId && affUserId !== userId) {
      return Response.json({ error: "Affiliate record does not match this payout request user." }, { status: 400 })
    }

    const destination = String(acct.stripe_connected_account_id ?? "").trim()
    const payoutsEnabled = Boolean(acct.stripe_payouts_enabled)
    const onboardingComplete = Boolean(acct.stripe_onboarding_complete)

    if (!destination) {
      return Response.json(
        { error: "Affiliate has no Stripe connected account. They must complete payout setup first." },
        { status: 400 }
      )
    }

    if (!payoutsEnabled) {
      return Response.json(
        { error: "Stripe payouts are not enabled for this connected account yet." },
        { status: 400 }
      )
    }

    if (!onboardingComplete) {
      return Response.json(
        { error: "Affiliate Stripe onboarding is not complete; cannot transfer." },
        { status: 400 }
      )
    }

    let stripe: ReturnType<typeof getStripeServer>
    try {
      stripe = getStripeServer()
    } catch {
      return Response.json({ error: "Stripe is not configured on the server." }, { status: 503 })
    }

    let transfer: Stripe.Transfer
    try {
      transfer = await stripe.transfers.create(
        {
          amount: cents,
          currency: CURRENCY,
          destination,
          metadata: {
            payout_request_id: payoutRequestId,
            user_id: userId,
            affiliate_id: affiliateId,
          },
        },
        { idempotencyKey: `affiliate_payout_${payoutRequestId}` }
      )
    } catch (e: unknown) {
      if (e instanceof Stripe.errors.StripeError) {
        const msg = stripeUserMessage(e)
        if (isDev) {
          console.error("[admin-payout-execute] Stripe transfer failed", {
            code: e.code,
            message: e.message,
            payoutRequestId,
          })
        }
        return Response.json({ error: msg }, { status: 502 })
      }
      throw e
    }

    if (isDev) {
      console.log("[admin-payout-execute] transfer response (source of truth for Mark Paid)", {
        raw: transfer,
        id: transfer.id,
        amount: transfer.amount,
        destination: transfer.destination,
        currency: transfer.currency,
        connectedAccountId: destination,
      })
    }

    const now = new Date().toISOString()

    let admin_notes: string | null
    if (body.adminNotes !== undefined) {
      admin_notes =
        body.adminNotes != null && String(body.adminNotes).trim()
          ? String(body.adminNotes).trim()
          : null
    } else {
      admin_notes =
        row.admin_notes != null && String(row.admin_notes).trim()
          ? String(row.admin_notes).trim()
          : null
    }

    const { error: updErr } = await supabaseServiceRole
      .from("affiliate_payout_requests")
      .update({
        status: "paid",
        paid_at: now,
        reviewed_at: now,
        reviewed_by: adminUser.id,
        payout_reference: transfer.id,
        stripe_transfer_id: transfer.id,
        admin_notes,
      })
      .eq("id", payoutRequestId)
      .eq("status", "approved")

    if (updErr) {
      if (isDev) console.error("[admin-payout-execute] DB update after Stripe success", updErr)
      return Response.json(
        {
          error:
            "Transfer succeeded but saving this request failed. Check Stripe Dashboard transfers and try again.",
        },
        { status: 500 }
      )
    }

    return Response.json({
      ok: true,
      stripe_transfer_id: transfer.id,
      amount_cents: cents,
      currency: CURRENCY,
    })
  } catch (e: unknown) {
    if (e instanceof Stripe.errors.StripeError) {
      console.error("[admin-payout-execute]", e)
      return Response.json({ error: stripeUserMessage(e) }, { status: 500 })
    }
    return jsonUserFacingError(e, 500, "admin-payout-execute")
  }
}
