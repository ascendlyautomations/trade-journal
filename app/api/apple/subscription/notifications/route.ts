import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { processAppleSubscriptionNotification } from "@/lib/appleSubscriptionNotifications"

export const runtime = "nodejs"

type NotificationBody = {
  signedPayload?: string
}

/**
 * App Store Server Notifications V2 webhook.
 * Authenticated by Apple's signed JWS — no TradeTraxs user session.
 */
export async function POST(req: Request) {
  let body: NotificationBody
  try {
    body = (await req.json()) as NotificationBody
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  const signedPayload = body.signedPayload?.trim()
  if (!signedPayload) {
    return Response.json({ error: "Missing signedPayload" }, { status: 400 })
  }

  try {
    const result = await processAppleSubscriptionNotification({
      supabase: supabaseServiceRole,
      signedPayload,
    })

    if (!result.ok) {
      return Response.json({ error: result.reason }, { status: result.status })
    }

    return Response.json({
      ok: true,
      duplicate: result.duplicate,
      applied: result.duplicate ? undefined : result.applied,
    })
  } catch (error) {
    console.error("[api/apple/subscription/notifications]", error)
    return Response.json(
      { error: "Failed to process notification" },
      { status: 500 }
    )
  }
}
