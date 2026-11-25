import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isLiveKitConfigured } from "@/lib/livekit/config.ts"
import {
  claimObsIngressCreationLease,
  commitObsIngressToSession,
  releaseObsIngressCreationLease,
  waitForSessionIngressAttachment,
} from "@/lib/livekit/tradeRoomBroadcastObsIngressLease.ts"
import {
  createObsRtmpIngress,
  deleteLiveKitIngress,
  ingressStatusLabel,
} from "@/lib/livekit/liveKitIngressService.ts"
import { logObsIngressLifecycle } from "@/lib/livekit/tradeRoomBroadcastIngressTelemetry.ts"
import { resolveTradeRoomBroadcastControlAccess } from "@/lib/livekit/tradeRoomBroadcastAccess.ts"
import {
  attachObsRtmpIngressToActiveSession,
  getActiveTradeRoomBroadcast,
} from "@/lib/livekit/tradeRoomBroadcastSession.ts"
import { primaryMediaPublisherIdentityForBroadcastSession } from "@/lib/livekit/tradeRoomBroadcastObsIdentity.ts"
import {
  consumeDurableUserRateLimit,
  rateLimitExceededResponse,
} from "@/lib/server/durableUserRateLimit.ts"
import { parseObsSessionBody } from "../_shared.ts"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

export async function POST(req: Request) {
  const { user, authError } = await getRouteUserAuth(req)
  if (!user?.id) {
    return Response.json(
      { error: "Unauthorized", detail: authError?.code ?? null },
      { status: 401 }
    )
  }

  if (!isLiveKitConfigured()) {
    return Response.json(
      { error: "Live streaming is not configured on the server." },
      { status: 503 }
    )
  }

  const rate = await consumeDurableUserRateLimit(
    user.id,
    "livekit_broadcast_control"
  )
  if (!rate.allowed) {
    return rateLimitExceededResponse(rate.retryAfterSec)
  }

  let body: unknown
  try {
    body = await req.json()
  } catch {
    return Response.json({ error: "Invalid JSON body." }, { status: 400 })
  }

  const parsed = parseObsSessionBody(body)
  if (!parsed) {
    return Response.json(
      { error: "roomId and sessionId are required." },
      { status: 400 }
    )
  }

  const access = await resolveTradeRoomBroadcastControlAccess(supabaseServiceRole, {
    userId: user.id,
    roomId: parsed.roomId,
  })

  if (!access.ok) {
    return Response.json({ error: access.error }, { status: access.status })
  }

  const active = await getActiveTradeRoomBroadcast(
    supabaseServiceRole,
    parsed.roomId,
    { skipRecoverStale: true, activeScope: "any" }
  )

  if (!active || active.id !== parsed.sessionId) {
    return Response.json(
      { error: "No active broadcast session found for this room." },
      { status: 404 }
    )
  }

  if (active.broadcasterUserId !== user.id) {
    return Response.json(
      { error: "Only the authorized broadcaster can create OBS credentials." },
      { status: 403 }
    )
  }

  if (active.livekitIngressId?.trim()) {
    return Response.json(
      {
        error:
          "This session already has OBS ingress. Revoke it before creating new credentials.",
      },
      { status: 409 }
    )
  }

  let leaseClaim = await claimObsIngressCreationLease(supabaseServiceRole, {
    roomId: parsed.roomId,
    sessionId: active.id,
    broadcasterUserId: user.id,
  })

  if (leaseClaim.kind === "unavailable") {
    // Pre-migration fallback: attach without distributed lease (single-instance dev only).
    leaseClaim = { kind: "claimed", leaseToken: "legacy" }
  } else if (leaseClaim.kind === "already_attached") {
    return Response.json(
      {
        error:
          "This session already has OBS ingress. Revoke it before creating new credentials.",
      },
      { status: 409 }
    )
  } else if (leaseClaim.kind === "in_progress") {
    const wait = await waitForSessionIngressAttachment(supabaseServiceRole, {
      roomId: parsed.roomId,
      sessionId: active.id,
    })
    if (wait.attached) {
      return Response.json(
        {
          error:
            "This session already has OBS ingress. Revoke it before creating new credentials.",
        },
        { status: 409 }
      )
    }
    return Response.json(
      {
        error:
          "OBS credentials are being created in another window. Wait a moment and try again.",
        code: "ingress_creation_in_progress",
      },
      { status: 423 }
    )
  } else if (
    leaseClaim.kind === "not_found" ||
    leaseClaim.kind === "forbidden"
  ) {
    return Response.json(
      { error: "No active broadcast session found for this room." },
      { status: 404 }
    )
  }

  const leaseToken =
    leaseClaim.kind === "claimed" ? leaseClaim.leaseToken : "legacy"
  const primaryIdentity = primaryMediaPublisherIdentityForBroadcastSession(active.id)
  const displayName = access.displayName?.trim() || "Live"

  logObsIngressLifecycle("create_ingress", {
    roomId: parsed.roomId,
    sessionId: active.id,
    leaseToken,
  })

  const created = await createObsRtmpIngress({
    roomId: parsed.roomId,
    participantIdentity: primaryIdentity,
    participantDisplayName: displayName,
  })

  if (!created.ok) {
    const isUnsupported =
      /not available|Ingress is not/i.test(created.error) ||
      created.error.includes("Enable Ingress")
    if (isUnsupported) {
      await releaseObsIngressCreationLease(supabaseServiceRole, {
        roomId: parsed.roomId,
        sessionId: active.id,
        broadcasterUserId: user.id,
        leaseToken: leaseToken === "legacy" ? null : leaseToken,
      })
    }
    logObsIngressLifecycle("create_ingress_failed", {
      roomId: parsed.roomId,
      sessionId: active.id,
      leaseToken,
      error: created.error,
    })
    return Response.json(
      { error: created.error },
      { status: isUnsupported ? 503 : 502 }
    )
  }

  const ingressId = created.info.ingressId?.trim() || ""
  if (!ingressId) {
    await releaseObsIngressCreationLease(supabaseServiceRole, {
      roomId: parsed.roomId,
      sessionId: active.id,
      broadcasterUserId: user.id,
      leaseToken: leaseToken === "legacy" ? null : leaseToken,
    })
    return Response.json(
      { error: "LiveKit did not return an ingress id." },
      { status: 502 }
    )
  }

  const attach =
    leaseToken !== "legacy"
      ? await commitObsIngressToSession(supabaseServiceRole, {
          roomId: parsed.roomId,
          sessionId: active.id,
          broadcasterUserId: user.id,
          leaseToken,
          livekitIngressId: ingressId,
          primaryMediaPublisherIdentity: primaryIdentity,
          ingressStatusLabel: ingressStatusLabel(created.info),
        })
      : await attachObsRtmpIngressToActiveSession(supabaseServiceRole, {
          roomId: parsed.roomId,
          broadcasterUserId: user.id,
          sessionId: active.id,
          livekitIngressId: ingressId,
          primaryMediaPublisherIdentity: primaryIdentity,
          ingressStatusLabel: ingressStatusLabel(created.info),
        })

  if (!attach.ok) {
    logObsIngressLifecycle("attach_ingress_failed", {
      roomId: parsed.roomId,
      sessionId: active.id,
      ingressId,
      leaseToken,
      error: attach.error,
    })
    const del = await deleteLiveKitIngress(ingressId)
    if (!del.ok) {
      logObsIngressLifecycle("delete_ingress_failed", {
        roomId: parsed.roomId,
        sessionId: active.id,
        ingressId,
        error: del.error,
        extra: { context: "rollback_after_attach_failure" },
      })
    } else {
      logObsIngressLifecycle("delete_ingress", {
        roomId: parsed.roomId,
        sessionId: active.id,
        ingressId,
        extra: { context: "rollback_after_attach_failure" },
      })
    }
    await releaseObsIngressCreationLease(supabaseServiceRole, {
      roomId: parsed.roomId,
      sessionId: active.id,
      broadcasterUserId: user.id,
      leaseToken: leaseToken === "legacy" ? null : leaseToken,
    })
    return Response.json({ error: attach.error }, { status: attach.status })
  }

  const rtmpUrl = created.info.url?.trim() || ""
  const streamKey = created.info.streamKey?.trim() || ""
  if (!rtmpUrl || !streamKey) {
    const del = await deleteLiveKitIngress(ingressId)
    if (!del.ok) {
      logObsIngressLifecycle("delete_ingress_failed", {
        roomId: parsed.roomId,
        sessionId: active.id,
        ingressId,
        error: del.error,
        extra: { context: "missing_rtmp_response" },
      })
    }
    await releaseObsIngressCreationLease(supabaseServiceRole, {
      roomId: parsed.roomId,
      sessionId: active.id,
      broadcasterUserId: user.id,
      leaseToken: leaseToken === "legacy" ? null : leaseToken,
    })
    return Response.json(
      { error: "LiveKit ingress response missing RTMP URL or stream key." },
      { status: 502 }
    )
  }

  return Response.json({
    broadcastSessionId: active.id,
    broadcastSource: "obs" as const,
    primaryMediaPublisherIdentity: primaryIdentity,
    livekitIngressId: ingressId,
    ingressStatusSnapshot: ingressStatusLabel(created.info),
    rtmpUrl,
    streamKey,
  })
}