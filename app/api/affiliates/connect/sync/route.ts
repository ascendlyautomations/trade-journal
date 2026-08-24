import Stripe from "stripe"
import { supabaseServiceRole, getRouteUser } from "@/app/api/_lib/getRouteUser"
import {
  AFFILIATE_CONNECT_SELECT,
  parseAffiliateConnectRow,
  stripeAccountToAffiliateConnectPatch,
} from "@/lib/affiliateStripeConnect"
import { getStripeServer } from "@/lib/stripeServer"
import {
  isStripeServerConfigured,
  resolveStripeServerConfig,
} from "@/lib/stripeServerConfig"
import {
  logAffiliateConnectSync,
  newAffiliateConnectSyncRequestId,
  stripeModeForLog,
  type AffiliateConnectSyncFailureCategory,
} from "@/lib/affiliateConnectSyncLog"
import { devLog } from "@/lib/devLog"
import { USER_FACING_ERROR_MESSAGES } from "@/lib/userFacingError"

export const runtime = "nodejs"

type SyncErrorBody = {
  ok: false
  error: string
  category: AffiliateConnectSyncFailureCategory
  skipped?: boolean
  retryable: boolean
}

type SyncSuccessBody = {
  ok: true
  skipped?: boolean
  affiliate: ReturnType<typeof parseAffiliateConnectRow> | null
  category?: "success" | "skipped"
}

function safeSyncError(status: number, body: SyncErrorBody): Response {
  return Response.json(body, { status })
}

function stripeNotConfiguredBody(isDev: boolean): SyncErrorBody {
  return {
    ok: false,
    category: "stripe_not_configured",
    skipped: true,
    retryable: false,
    error: isDev
      ? "Stripe Connect sync requires STRIPE_SECRET_KEY in the server environment."
      : USER_FACING_ERROR_MESSAGES.BILLING_UNAVAILABLE,
  }
}

function stripeInvalidFormatBody(isDev: boolean): SyncErrorBody {
  return {
    ok: false,
    category: "stripe_invalid_format",
    skipped: true,
    retryable: false,
    error: isDev
      ? "STRIPE_SECRET_KEY is present but not a valid Stripe secret key format."
      : USER_FACING_ERROR_MESSAGES.BILLING_UNAVAILABLE,
  }
}

function classifyStripeSyncFailure(error: Stripe.errors.StripeError): {
  status: number
  body: SyncErrorBody
} {
  if (
    error instanceof Stripe.errors.StripeInvalidRequestError &&
    (error.statusCode === 404 ||
      error.code === "resource_missing" ||
      /no such account/i.test(error.message ?? ""))
  ) {
    return {
      status: 422,
      body: {
        ok: false,
        category: "stripe_account_missing",
        skipped: true,
        retryable: false,
        error:
          "Your Stripe Connect account is no longer available. Restart payout setup from Settings.",
      },
    }
  }

  if (
    error instanceof Stripe.errors.StripeAuthenticationError ||
    error instanceof Stripe.errors.StripePermissionError
  ) {
    return {
      status: 503,
      body: {
        ok: false,
        category: "stripe_auth_invalid",
        retryable: false,
        error: USER_FACING_ERROR_MESSAGES.BILLING_UNAVAILABLE,
      },
    }
  }

  if (
    error instanceof Stripe.errors.StripeConnectionError ||
    error instanceof Stripe.errors.StripeAPIError
  ) {
    return {
      status: 503,
      body: {
        ok: false,
        category: "stripe_transient",
        retryable: true,
        error: USER_FACING_ERROR_MESSAGES.BILLING_UNAVAILABLE,
      },
    }
  }

  return {
    status: 422,
    body: {
      ok: false,
      category: "stripe_deterministic",
      retryable: false,
      error:
        "Could not refresh Stripe Connect status. Try again from payout setup.",
    },
  }
}

/**
 * Affiliate-only: syncs Stripe Connect status for `affiliates.user_id === auth user`.
 * Requires session via cookies or `Authorization: Bearer` (browser client uses Bearer).
 */
export async function POST(req: Request) {
  const started = Date.now()
  const requestId = newAffiliateConnectSyncRequestId()
  const isDev = process.env.NODE_ENV === "development"
  const environment = process.env.VERCEL_ENV ?? process.env.NODE_ENV ?? "unknown"
  const authHeader = req.headers.get("authorization") ?? ""
  const hasBearer =
    authHeader.startsWith("Bearer ") && authHeader.slice("Bearer ".length).trim().length > 0

  const finish = (
    status: number,
    category: AffiliateConnectSyncFailureCategory | "success" | "skipped",
    fields: {
      viewerPresent: boolean
      affiliatePresent: boolean
      connectedAccountPresent: boolean
      retryable: boolean
    }
  ) => {
    logAffiliateConnectSync({
      requestId,
      environment,
      elapsedMs: Date.now() - started,
      viewerPresent: fields.viewerPresent,
      affiliatePresent: fields.affiliatePresent,
      connectedAccountPresent: fields.connectedAccountPresent,
      stripeConfigured: isStripeServerConfigured(),
      stripeMode: stripeModeForLog(),
      category,
      retryable: fields.retryable,
      status,
    })
  }

  try {
    const user = await getRouteUser(req)

    if (isDev) {
      devLog("[connect/sync] auth probe", {
        requestId,
        authUserId: user?.id ?? null,
        hasBearerToken: hasBearer,
        userResolved: Boolean(user?.id),
      })
    }

    if (!user?.id) {
      finish(401, "unauthenticated", {
        viewerPresent: false,
        affiliatePresent: false,
        connectedAccountPresent: false,
        retryable: false,
      })
      return Response.json(
        { error: USER_FACING_ERROR_MESSAGES.SESSION_EXPIRED },
        { status: 401 }
      )
    }

    const stripeConfig = resolveStripeServerConfig()
    if (stripeConfig.status === "missing") {
      const body = stripeNotConfiguredBody(isDev)
      finish(503, body.category, {
        viewerPresent: true,
        affiliatePresent: false,
        connectedAccountPresent: false,
        retryable: false,
      })
      return safeSyncError(503, body)
    }
    if (stripeConfig.status === "invalid_format") {
      const body = stripeInvalidFormatBody(isDev)
      finish(503, body.category, {
        viewerPresent: true,
        affiliatePresent: false,
        connectedAccountPresent: false,
        retryable: false,
      })
      return safeSyncError(503, body)
    }

    let stripe: ReturnType<typeof getStripeServer>
    try {
      stripe = getStripeServer()
    } catch {
      const body = stripeNotConfiguredBody(isDev)
      finish(503, body.category, {
        viewerPresent: true,
        affiliatePresent: false,
        connectedAccountPresent: false,
        retryable: false,
      })
      return safeSyncError(503, body)
    }

    const { data: affiliate, error: affErr } = await supabaseServiceRole
      .from("affiliates")
      .select("id, stripe_connected_account_id")
      .eq("user_id", user.id)
      .maybeSingle()

    if (affErr) {
      finish(500, "database_read", {
        viewerPresent: true,
        affiliatePresent: false,
        connectedAccountPresent: false,
        retryable: false,
      })
      if (isDev) console.error("[connect/sync] affiliate select", affErr)
      return Response.json({ error: "Could not load affiliate row" }, { status: 500 })
    }

    if (!affiliate?.id) {
      finish(403, "affiliate_missing", {
        viewerPresent: true,
        affiliatePresent: false,
        connectedAccountPresent: false,
        retryable: false,
      })
      return Response.json(
        { ok: false, error: "No affiliate record for this account." },
        { status: 403 }
      )
    }

    const acctId =
      affiliate.stripe_connected_account_id != null
        ? String(affiliate.stripe_connected_account_id).trim()
        : ""

    if (!acctId) {
      finish(200, "skipped", {
        viewerPresent: true,
        affiliatePresent: true,
        connectedAccountPresent: false,
        retryable: false,
      })
      return Response.json({
        ok: true,
        skipped: true,
        category: "skipped",
        affiliate: null,
      } satisfies SyncSuccessBody)
    }

    let account: Stripe.Account
    try {
      account = await stripe.accounts.retrieve(acctId)
    } catch (stripeErr) {
      if (stripeErr instanceof Stripe.errors.StripeError) {
        const classified = classifyStripeSyncFailure(stripeErr)
        finish(classified.status, classified.body.category, {
          viewerPresent: true,
          affiliatePresent: true,
          connectedAccountPresent: true,
          retryable: classified.body.retryable,
        })
        if (isDev) {
          console.error("[connect/sync] stripe.accounts.retrieve", {
            requestId,
            code: stripeErr.code,
            type: stripeErr.type,
          })
        }
        return safeSyncError(classified.status, classified.body)
      }
      throw stripeErr
    }

    const patch = stripeAccountToAffiliateConnectPatch(account)

    const { error: updateErr } = await supabaseServiceRole
      .from("affiliates")
      .update(patch)
      .eq("user_id", user.id)

    if (updateErr) {
      finish(500, "database_write", {
        viewerPresent: true,
        affiliatePresent: true,
        connectedAccountPresent: true,
        retryable: false,
      })
      if (isDev) console.error("[connect/sync] affiliate update", updateErr)
      return Response.json(
        { ok: false, error: "Could not save Stripe Connect status." },
        { status: 500 }
      )
    }

    const { data: row, error: rowErr } = await supabaseServiceRole
      .from("affiliates")
      .select(AFFILIATE_CONNECT_SELECT)
      .eq("user_id", user.id)
      .maybeSingle()

    if (rowErr) {
      finish(500, "database_read", {
        viewerPresent: true,
        affiliatePresent: true,
        connectedAccountPresent: true,
        retryable: false,
      })
      if (isDev) console.error("[connect/sync] affiliate reselect", rowErr)
      return Response.json(
        { ok: false, error: "Could not load updated affiliate row." },
        { status: 500 }
      )
    }

    if (!row || typeof row !== "object") {
      finish(200, "success", {
        viewerPresent: true,
        affiliatePresent: true,
        connectedAccountPresent: true,
        retryable: false,
      })
      return Response.json({ ok: true, affiliate: null, category: "success" })
    }

    finish(200, "success", {
      viewerPresent: true,
      affiliatePresent: true,
      connectedAccountPresent: true,
      retryable: false,
    })

    return Response.json({
      ok: true,
      skipped: false,
      category: "success",
      affiliate: parseAffiliateConnectRow(row as Record<string, unknown>),
    } satisfies SyncSuccessBody)
  } catch (e: unknown) {
    if (e instanceof Stripe.errors.StripeError) {
      const classified = classifyStripeSyncFailure(e)
      finish(classified.status, classified.body.category, {
        viewerPresent: false,
        affiliatePresent: false,
        connectedAccountPresent: false,
        retryable: classified.body.retryable,
      })
      if (isDev) console.error("[connect/sync] stripe error", { requestId, type: e.type })
      return safeSyncError(classified.status, classified.body)
    }
    finish(500, "unexpected", {
      viewerPresent: false,
      affiliatePresent: false,
      connectedAccountPresent: false,
      retryable: false,
    })
    if (isDev) console.error("[connect/sync] unexpected", e)
    return Response.json(
      { ok: false, error: USER_FACING_ERROR_MESSAGES.UNKNOWN_ERROR },
      { status: 500 }
    )
  }
}
