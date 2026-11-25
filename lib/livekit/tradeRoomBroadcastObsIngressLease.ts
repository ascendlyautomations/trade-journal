import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import { logObsIngressLifecycle } from "./tradeRoomBroadcastIngressTelemetry.ts"

const DEFAULT_LEASE_TTL_SECONDS = 180
const ATTACH_WAIT_MS = 45_000
const ATTACH_POLL_MS = 750

export type ObsIngressLeaseClaim =
  | { kind: "claimed"; leaseToken: string }
  | { kind: "in_progress"; leaseToken: string }
  | { kind: "already_attached" }
  | { kind: "not_found" }
  | { kind: "forbidden" }
  | { kind: "unavailable" }

function parseClaimResult(raw: string | null | undefined): ObsIngressLeaseClaim {
  const text = (raw ?? "").trim()
  if (!text) return { kind: "unavailable" }
  if (text === "NOT_FOUND") return { kind: "not_found" }
  if (text === "FORBIDDEN") return { kind: "forbidden" }
  if (text === "ALREADY_ATTACHED") return { kind: "already_attached" }
  if (text.startsWith("IN_PROGRESS:")) {
    return { kind: "in_progress", leaseToken: text.slice("IN_PROGRESS:".length) }
  }
  if (text.startsWith("CLAIMED:")) {
    return { kind: "claimed", leaseToken: text.slice("CLAIMED:".length) }
  }
  return { kind: "unavailable" }
}

function broadcastsTable(admin: SupabaseClient<Database>) {
  return admin.from("room_live_broadcasts")
}

export async function claimObsIngressCreationLease(
  admin: SupabaseClient<Database>,
  options: {
    roomId: string
    sessionId: string
    broadcasterUserId: string
    leaseTtlSeconds?: number
  }
): Promise<ObsIngressLeaseClaim> {
  const { roomId, sessionId, broadcasterUserId } = options
  const ttl = options.leaseTtlSeconds ?? DEFAULT_LEASE_TTL_SECONDS

  const rpc = await admin.rpc("trade_room_broadcast_claim_ingress_lease", {
    p_session_id: sessionId,
    p_room_id: roomId,
    p_broadcaster_id: broadcasterUserId,
    p_ttl_seconds: ttl,
  })

  if (!rpc.error) {
    const claim = parseClaimResult(typeof rpc.data === "string" ? rpc.data : null)
    logObsIngressLifecycle(
      claim.kind === "already_attached"
        ? "claim_lease_already_attached"
        : claim.kind === "in_progress"
          ? "claim_lease_in_progress"
          : "claim_lease",
      {
        roomId,
        sessionId,
        leaseToken: claim.kind === "claimed" || claim.kind === "in_progress" ? claim.leaseToken : null,
        extra: { result: claim.kind },
      }
    )
    return claim
  }

  if (rpc.error.message?.includes("trade_room_broadcast_claim_ingress_lease")) {
    return { kind: "unavailable" }
  }

  console.error("[livekit/obs-ingress] claim lease rpc failed", rpc.error.message)
  return { kind: "unavailable" }
}

export async function releaseObsIngressCreationLease(
  admin: SupabaseClient<Database>,
  options: {
    roomId: string
    sessionId: string
    broadcasterUserId: string
    leaseToken?: string | null
  }
): Promise<void> {
  const { roomId, sessionId, broadcasterUserId } = options
  const leaseToken = options.leaseToken?.trim() || null

  const rpc = await admin.rpc("trade_room_broadcast_release_ingress_lease", {
    p_session_id: sessionId,
    p_room_id: roomId,
    p_broadcaster_id: broadcasterUserId,
    p_lease_token: leaseToken ?? undefined,
  })
  if (rpc.error) {
    console.error("[livekit/obs-ingress] release lease failed", rpc.error.message)
  }
  logObsIngressLifecycle("release_lease", {
    roomId,
    sessionId,
    leaseToken,
  })
}

export async function commitObsIngressToSession(
  admin: SupabaseClient<Database>,
  options: {
    roomId: string
    sessionId: string
    broadcasterUserId: string
    leaseToken: string
    livekitIngressId: string
    primaryMediaPublisherIdentity: string
    ingressStatusLabel: string | null
  }
): Promise<{ ok: true } | { ok: false; status: number; error: string }> {
  const rpc = await admin.rpc("trade_room_broadcast_commit_ingress", {
    p_session_id: options.sessionId,
    p_room_id: options.roomId,
    p_broadcaster_id: options.broadcasterUserId,
    p_lease_token: options.leaseToken,
    p_ingress_id: options.livekitIngressId.trim(),
    p_primary_identity: options.primaryMediaPublisherIdentity,
    p_status_label: options.ingressStatusLabel?.trim() ?? "",
  })

  if (rpc.error) {
    console.error("[livekit/obs-ingress] commit ingress rpc failed", rpc.error.message)
    return {
      ok: false,
      status: 500,
      error: "Could not attach OBS ingress to session.",
    }
  }

  if (rpc.data !== true) {
    logObsIngressLifecycle("attach_ingress_failed", {
      roomId: options.roomId,
      sessionId: options.sessionId,
      ingressId: options.livekitIngressId,
      leaseToken: options.leaseToken,
      error: "commit_not_applied",
    })
    return {
      ok: false,
      status: 409,
      error: "No active broadcast session found for this room.",
    }
  }

  logObsIngressLifecycle("attach_ingress", {
    roomId: options.roomId,
    sessionId: options.sessionId,
    ingressId: options.livekitIngressId,
    leaseToken: options.leaseToken,
  })
  return { ok: true }
}

export async function waitForSessionIngressAttachment(
  admin: SupabaseClient<Database>,
  options: {
    roomId: string
    sessionId: string
    maxWaitMs?: number
  }
): Promise<{ attached: boolean; livekitIngressId: string | null }> {
  const deadline = Date.now() + (options.maxWaitMs ?? ATTACH_WAIT_MS)
  while (Date.now() < deadline) {
    const { data, error } = await broadcastsTable(admin)
      .select("livekit_ingress_id, ended_at")
      .eq("id", options.sessionId)
      .eq("room_id", options.roomId)
      .maybeSingle()

    if (error) break
    if (!data || data.ended_at != null) {
      return { attached: false, livekitIngressId: null }
    }
    const ingressId = (data.livekit_ingress_id as string | null)?.trim() || ""
    if (ingressId) {
      return { attached: true, livekitIngressId: ingressId }
    }
    await new Promise((resolve) => setTimeout(resolve, ATTACH_POLL_MS))
  }
  return { attached: false, livekitIngressId: null }
}