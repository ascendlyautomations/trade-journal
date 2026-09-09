import type { User } from "@supabase/supabase-js"
import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { createRouteSupabaseClient } from "@/app/api/_lib/routeSupabaseClient"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"
import {
  notifyTradeRoomJoinAccepted,
  notifyTradeRoomJoinDeclined,
  syncTradeRoomJoinRequestNotifications,
} from "@/lib/server/notifications/handlers/tradeRoomJoinRequestNotify"

type PendingJoinRequest = {
  id: string
  room_id: string
  user_id: string
  status: string
}

async function loadPendingJoinRequest(
  requestId: string
): Promise<{ data: PendingJoinRequest | null; error: string | null }> {
  const { data, error } = await supabaseServiceRole
    .from("room_join_requests")
    .select("id, room_id, user_id, status")
    .eq("id", requestId)
    .eq("status", "pending")
    .maybeSingle()

  if (error) {
    console.error("[trade-room-join-requests] lookup failed", error)
    return { data: null, error: toUserFacingErrorMessage(error) }
  }

  return { data: data as PendingJoinRequest | null, error: null }
}

async function resolveViaRpc(
  req: Request,
  requestId: string,
  action: "approve" | "decline"
): Promise<{ ok: true } | { ok: false; status: number; error: string }> {
  const client = await createRouteSupabaseClient(req)
  const { error } = await client.rpc("rpc_v1_resolve_trade_room_join_request", {
    p_request_id: requestId,
    p_action: action,
  })

  if (error) {
    console.error("[trade-room-join-requests] resolve RPC failed", error)
    const message = toUserFacingErrorMessage(error)
    if (error.code === "42501" || message.toLowerCase().includes("owner")) {
      return { ok: false, status: 403, error: "You cannot manage this join request." }
    }
    if (error.code === "P0002") {
      return { ok: false, status: 404, error: "Join request not found." }
    }
    if (message.includes("request_not_pending")) {
      return { ok: false, status: 409, error: "This join request is no longer pending." }
    }
    return { ok: false, status: 500, error: message }
  }

  return { ok: true }
}

export async function approveTradeRoomJoinRequest(
  user: User,
  req: Request,
  requestId: string
): Promise<{ ok: true } | { ok: false; status: number; error: string }> {
  const { data: pending, error: lookupErr } = await loadPendingJoinRequest(requestId)
  if (lookupErr) {
    return { ok: false, status: 500, error: lookupErr }
  }
  if (!pending) {
    return { ok: false, status: 404, error: "Pending join request not found." }
  }

  const resolved = await resolveViaRpc(req, requestId, "approve")
  if (!resolved.ok) return resolved

  await syncTradeRoomJoinRequestNotifications(requestId, "approved")
  await notifyTradeRoomJoinAccepted({
    requesterUserId: pending.user_id,
    resolverUserId: user.id,
    roomId: pending.room_id,
  })

  return { ok: true }
}

export async function declineTradeRoomJoinRequest(
  user: User,
  req: Request,
  requestId: string
): Promise<{ ok: true } | { ok: false; status: number; error: string }> {
  const { data: pending, error: lookupErr } = await loadPendingJoinRequest(requestId)
  if (lookupErr) {
    return { ok: false, status: 500, error: lookupErr }
  }
  if (!pending) {
    return { ok: false, status: 404, error: "Pending join request not found." }
  }

  const resolved = await resolveViaRpc(req, requestId, "decline")
  if (!resolved.ok) return resolved

  await syncTradeRoomJoinRequestNotifications(requestId, "rejected")
  await notifyTradeRoomJoinDeclined({
    requesterUserId: pending.user_id,
    resolverUserId: user.id,
    roomId: pending.room_id,
  })

  return { ok: true }
}
