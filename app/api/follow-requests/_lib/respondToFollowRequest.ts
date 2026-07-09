import type { User } from "@supabase/supabase-js"
import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"

type PendingRequest = {
  id: string
  requester_id: string
  target_id: string
}

async function loadPendingRequestForTarget(
  requestId: string,
  targetUserId: string
): Promise<{ data: PendingRequest | null; error: string | null }> {
  const { data, error } = await supabaseServiceRole
    .from("follow_requests")
    .select("id, requester_id, target_id")
    .eq("id", requestId)
    .eq("target_id", targetUserId)
    .eq("status", "pending")
    .maybeSingle()

  if (error) {
    console.error("[follow-requests] lookup failed", error)
    return { data: null, error: toUserFacingErrorMessage(error) }
  }

  return { data: data as PendingRequest | null, error: null }
}

async function removeFollowRequestNotification(
  targetId: string,
  requesterId: string
): Promise<void> {
  const { error } = await supabaseServiceRole
    .from("notifications")
    .delete()
    .eq("user_id", targetId)
    .eq("sender_id", requesterId)
    .eq("type", "follow_request")

  if (error) {
    console.error("[follow-requests] notification remove failed", error)
  }
}

export async function approveFollowRequest(
  user: User,
  requestId: string
): Promise<{ ok: true } | { ok: false; status: number; error: string }> {
  const { data: req, error: lookupErr } = await loadPendingRequestForTarget(
    requestId,
    user.id
  )

  if (lookupErr) {
    return { ok: false, status: 500, error: lookupErr }
  }

  if (!req) {
    return { ok: false, status: 404, error: "Pending follow request not found" }
  }

  const { error: followErr } = await supabaseServiceRole.from("followers").insert({
    follower_id: req.requester_id,
    following_id: req.target_id,
  })

  if (followErr && followErr.code !== "23505") {
    console.error("[follow-requests] followers insert failed", followErr)
    return { ok: false, status: 500, error: toUserFacingErrorMessage(followErr) }
  }

  const { error: deleteErr } = await supabaseServiceRole
    .from("follow_requests")
    .delete()
    .eq("id", req.id)

  if (deleteErr) {
    console.error("[follow-requests] request delete failed", deleteErr)
    return { ok: false, status: 500, error: toUserFacingErrorMessage(deleteErr) }
  }

  await removeFollowRequestNotification(req.target_id, req.requester_id)

  const { error: notifErr } = await supabaseServiceRole.from("notifications").insert({
    user_id: req.target_id,
    sender_id: req.requester_id,
    type: "follow",
  })

  if (notifErr) {
    if (notifErr.code !== "23505") {
      console.error("[follow-requests] follow notification insert failed", notifErr)
      return { ok: false, status: 500, error: toUserFacingErrorMessage(notifErr) }
    }
  }

  return { ok: true }
}

export async function declineFollowRequest(
  user: User,
  requestId: string
): Promise<{ ok: true } | { ok: false; status: number; error: string }> {
  const { data: req, error: lookupErr } = await loadPendingRequestForTarget(
    requestId,
    user.id
  )

  if (lookupErr) {
    return { ok: false, status: 500, error: lookupErr }
  }

  if (!req) {
    return { ok: false, status: 404, error: "Pending follow request not found" }
  }

  const { error: deleteErr } = await supabaseServiceRole
    .from("follow_requests")
    .delete()
    .eq("id", req.id)

  if (deleteErr) {
    console.error("[follow-requests] request delete failed", deleteErr)
    return { ok: false, status: 500, error: toUserFacingErrorMessage(deleteErr) }
  }

  await removeFollowRequestNotification(req.target_id, req.requester_id)

  return { ok: true }
}
