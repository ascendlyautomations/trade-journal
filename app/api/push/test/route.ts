import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  getApnsRuntimeInfo,
  isApnsConfigured,
  sendApnsAlert,
} from "@/lib/server/push/apns"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

/** TEMPORARY — mask device tokens in diagnostics. Remove with other temp logs. */
function maskDeviceToken(token: string): string {
  const t = token.trim()
  if (t.length < 14) return "***"
  return `${t.slice(0, 8)}...${t.slice(-6)}`
}

/**
 * Send a self-test APNs alert to every iOS token for the signed-in user.
 * Infrastructure verification only — not a product notification type.
 *
 * TEMPORARY: surfaces exact APNs rejection reasons for debugging.
 * Remove verbose diagnostics after E2E verification.
 */
export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  if (!isApnsConfigured()) {
    const apns = getApnsRuntimeInfo()
    return Response.json(
      {
        error: "apns_not_configured",
        apns,
        env: {
          hasKeyId: Boolean(process.env.APNS_KEY_ID?.trim()),
          hasTeamId: Boolean(process.env.APNS_TEAM_ID?.trim()),
          hasPrivateKey: Boolean(process.env.APNS_PRIVATE_KEY?.trim()),
        },
        hint: "Set APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY (and APNS_BUNDLE_ID / APNS_PRODUCTION) on the server.",
      },
      { status: 503 }
    )
  }

  const { data: tokens, error: tokenErr } = await supabaseServiceRole
    .from("device_push_tokens")
    .select("device_token")
    .eq("user_id", user.id)
    .eq("platform", "ios")

  if (tokenErr) {
    console.error("[api/push/test] token lookup failed", tokenErr)
    return Response.json({ error: tokenErr.message }, { status: 500 })
  }

  if (!tokens?.length) {
    return Response.json(
      {
        error: "no_device_tokens",
        hint: "Open the iOS app while signed in and allow notifications so /api/push/register can store a token.",
      },
      { status: 404 }
    )
  }

  const results: Array<{
    ok: boolean
    tokenPreview: string
    apnsReason: string | null
    apnsStatus: number | null
    invalidToken: boolean
  }> = []

  for (const row of tokens) {
    const deviceToken = String(row.device_token ?? "").trim()
    if (!deviceToken) continue
    const tokenPreview = maskDeviceToken(deviceToken)
    const result = await sendApnsAlert(deviceToken, {
      title: "TradeTraxs",
      body: "Push notifications are working.",
      href: "/notifications",
      badge: 1,
      notificationType: "push_test",
    })
    if (result.ok) {
      // TEMPORARY diagnostics
      console.info("[api/push/test:temp] APNs accepted", { tokenPreview })
      results.push({
        ok: true,
        tokenPreview,
        apnsReason: null,
        apnsStatus: 200,
        invalidToken: false,
      })
    } else {
      // TEMPORARY — do not swallow APNs rejection reasons.
      console.error("[api/push/test:temp] APNs rejected", {
        tokenPreview,
        apnsReason: result.reason,
        apnsStatus: result.status,
        invalidToken: result.invalidToken,
      })
      results.push({
        ok: false,
        tokenPreview,
        apnsReason: result.reason,
        apnsStatus: result.status,
        invalidToken: result.invalidToken,
      })
      if (result.invalidToken) {
        await supabaseServiceRole
          .from("device_push_tokens")
          .delete()
          .eq("device_token", deviceToken)
      }
    }
  }

  const sent = results.filter((r) => r.ok).length
  const failures = results.filter((r) => !r.ok)
  const primaryFailure = failures[0] ?? null

  return Response.json({
    ok: sent > 0,
    sent,
    attempted: results.length,
    results,
    // Exact APNs reason when delivery failed (e.g. BadDeviceToken, InvalidProviderToken).
    ...(sent === 0 && primaryFailure
      ? {
          error: "apns_delivery_failed",
          apnsReason: primaryFailure.apnsReason,
          apnsStatus: primaryFailure.apnsStatus,
        }
      : {}),
    apns: getApnsRuntimeInfo(),
  })
}
