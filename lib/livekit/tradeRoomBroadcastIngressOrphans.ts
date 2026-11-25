import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import { IngressState_Status, type IngressInfo } from "@livekit/protocol"
import {
  deleteLiveKitIngress,
  getLiveKitIngressClient,
} from "./liveKitIngressService.ts"
import { liveKitBroadcastRoomName } from "./liveKitRoomName.ts"
import { logObsIngressLifecycle } from "./tradeRoomBroadcastIngressTelemetry.ts"

const ORPHAN_MIN_AGE_MS = 12 * 60 * 1000
const MAX_ORPHAN_DELETES_PER_RUN = 8
const PROTECTED_RECENT_MS = 6 * 60 * 1000

function isTradetraxsIngressName(name: string | undefined): boolean {
  const n = (name ?? "").trim()
  return n.startsWith("tt-broadcast-")
}

function ingressCreatedAtMs(info: IngressInfo): number | null {
  const raw = (info as { createdAt?: bigint | number | string | null }).createdAt
  if (raw == null) return null
  if (typeof raw === "bigint") return Number(raw) * 1000
  if (typeof raw === "number") return raw > 1e12 ? raw : raw * 1000
  if (typeof raw === "string") {
    const n = Number(raw)
    if (!Number.isNaN(n)) return n > 1e12 ? n : n * 1000
    const parsed = Date.parse(raw)
    return Number.isNaN(parsed) ? null : parsed
  }
  return null
}

/**
 * Bounded orphan sweep: TradeTraxs-named ingresses not referenced by an active session
 * or a recent in-progress lease / ended session.
 */
export async function cleanupOrphanTradeRoomIngresses(
  admin: SupabaseClient<Database>,
  options: { roomId?: string } = {}
): Promise<{ examined: number; deleted: number }> {
  const client = getLiveKitIngressClient()
  if (!client) return { examined: 0, deleted: 0 }

  const roomName = options.roomId
    ? liveKitBroadcastRoomName(options.roomId)
    : undefined

  let items: Awaited<ReturnType<typeof client.listIngress>>
  try {
    items = await client.listIngress(
      roomName ? { roomName } : ({} as { roomName?: string })
    )
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    console.error("[livekit/obs-ingress] orphan list failed", message)
    return { examined: 0, deleted: 0 }
  }

  const candidates = items.filter(
    (row) =>
      isTradetraxsIngressName(row.name) &&
      (row.ingressId?.trim()?.length ?? 0) > 0
  )

  if (!candidates.length) return { examined: 0, deleted: 0 }

  const now = Date.now()

  let query = admin
    .from("room_live_broadcasts")
    .select("livekit_ingress_id, ingress_creation_lease_at, ended_at")
    .is("ended_at", null)

  if (options.roomId) {
    query = query.eq("room_id", options.roomId)
  }

  const { data: rows } = await query
  const protectedIds = new Set<string>()
  for (const row of rows ?? []) {
    const id = (row.livekit_ingress_id as string | null)?.trim()
    if (id) protectedIds.add(id)
    const leaseAt = row.ingress_creation_lease_at as string | null
    if (leaseAt && !row.ended_at && new Date(leaseAt).getTime() > now - PROTECTED_RECENT_MS) {
      // Fresh in-progress creation lease — do not delete ingress that may attach momentarily.
    }
  }

  let deleted = 0
  let examined = 0

  for (const info of candidates) {
    if (deleted >= MAX_ORPHAN_DELETES_PER_RUN) break
    examined += 1
    const ingressId = info.ingressId?.trim() ?? ""
    if (!ingressId || protectedIds.has(ingressId)) continue

    const createdAt = ingressCreatedAtMs(info)
    if (createdAt != null && now - createdAt < ORPHAN_MIN_AGE_MS) continue

    const status = info.state?.status
    if (status === IngressState_Status.ENDPOINT_PUBLISHING) continue

    const del = await deleteLiveKitIngress(ingressId)
    if (del.ok) {
      deleted += 1
      logObsIngressLifecycle("orphan_ingress_deleted", {
        roomId: options.roomId ?? "",
        sessionId: "",
        ingressId,
        extra: { ingressName: info.name, status: String(status ?? "") },
      })
    } else {
      logObsIngressLifecycle("delete_ingress_failed", {
        roomId: options.roomId ?? "",
        sessionId: "",
        ingressId,
        error: del.error,
        extra: { context: "orphan_sweep" },
      })
    }
  }

  return { examined, deleted }
}