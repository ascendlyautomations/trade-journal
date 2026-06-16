import type { SupabaseClient } from "@supabase/supabase-js"
import { createFollowNotification } from "@/lib/createFollowNotification"
import { createFollowRequestNotification } from "@/lib/createFollowRequestNotification"
import {
  notifyGettingStartedChecklistMaybeCompleted,
} from "@/lib/gettingStartedProgressSync"
import {
  removeFollowNotification,
  removeFollowRequestNotification,
} from "@/lib/followNotifications"

export type FollowUiState = "none" | "following" | "requested"

export type FollowUiSnapshot = {
  state: FollowUiState
  /** Profile user follows the viewer (reverse edge exists). */
  followsYou: boolean
}

export function isMutualFollow(
  state: FollowUiState,
  followsYou: boolean
): boolean {
  return state === "following" && followsYou
}

/** Primary action label for Follow / Follow Back / Requested (not the dropdown trigger). */
export function followButtonLabel(
  state: FollowUiState,
  followsYou: boolean
): string {
  if (state === "following") return "Following"
  if (state === "requested") return "Requested"
  if (followsYou) return "Follow Back"
  return "Follow"
}

/** Dropdown trigger text when the viewer already follows the profile user. */
export function followRelationshipTriggerLabel(
  state: FollowUiState,
  followsYou: boolean
): string | null {
  if (state !== "following") return null
  return isMutualFollow(state, followsYou) ? "Friends" : "Following"
}

export async function loadFollowUiSnapshot(
  supabase: SupabaseClient,
  viewerId: string | null | undefined,
  profileUserId: string | null | undefined
): Promise<FollowUiSnapshot> {
  if (!viewerId || !profileUserId || viewerId === profileUserId) {
    return { state: "none", followsYou: false }
  }

  const [followRes, requestRes, followsYouRes] = await Promise.all([
    supabase
      .from("followers")
      .select("follower_id")
      .eq("follower_id", viewerId)
      .eq("following_id", profileUserId)
      .maybeSingle(),
    supabase
      .from("follow_requests")
      .select("id")
      .eq("requester_id", viewerId)
      .eq("target_id", profileUserId)
      .eq("status", "pending")
      .maybeSingle(),
    supabase
      .from("followers")
      .select("follower_id")
      .eq("follower_id", profileUserId)
      .eq("following_id", viewerId)
      .maybeSingle(),
  ])

  let state: FollowUiState = "none"
  if (followRes.data) state = "following"
  else if (requestRes.data) state = "requested"

  return { state, followsYou: Boolean(followsYouRes.data) }
}

export async function loadFollowUiState(
  supabase: SupabaseClient,
  followerId: string | null | undefined,
  targetId: string | null | undefined
): Promise<FollowUiState> {
  const { state } = await loadFollowUiSnapshot(supabase, followerId, targetId)
  return state
}

export async function followOrRequest(
  supabase: SupabaseClient,
  followerId: string,
  target: { id: string; is_private?: boolean | null }
): Promise<{ ok: true; state: FollowUiState } | { ok: false; message: string }> {
  if (!followerId || !target.id || followerId === target.id) {
    return { ok: false, message: "Invalid follow target" }
  }

  const isPrivate = target.is_private === true

  if (isPrivate) {
    const { error } = await supabase.from("follow_requests").insert({
      requester_id: followerId,
      target_id: target.id,
      status: "pending",
    })

    if (error) {
      console.error("[follow] request insert failed", error)
      return { ok: false, message: error.message }
    }

    await createFollowRequestNotification(supabase, followerId, target.id)
    return { ok: true, state: "requested" }
  }

  const { error } = await supabase.from("followers").insert({
    follower_id: followerId,
    following_id: target.id,
  })

  if (error) {
    console.error("[follow] insert failed", error)
    return { ok: false, message: error.message }
  }

  await createFollowNotification(supabase, followerId, target.id)
  notifyGettingStartedChecklistMaybeCompleted()
  return { ok: true, state: "following" }
}

export async function unfollowOrCancelRequest(
  supabase: SupabaseClient,
  followerId: string,
  targetId: string,
  currentState: FollowUiState
): Promise<{ ok: true; state: FollowUiState } | { ok: false; message: string }> {
  if (!followerId || !targetId) {
    return { ok: false, message: "Invalid unfollow target" }
  }

  if (currentState === "following") {
    const { error } = await supabase
      .from("followers")
      .delete()
      .eq("follower_id", followerId)
      .eq("following_id", targetId)

    if (error) {
      console.error("[follow] delete failed", error)
      return { ok: false, message: error.message }
    }

    await removeFollowNotification(supabase, followerId, targetId)
    return { ok: true, state: "none" }
  }

  if (currentState === "requested") {
    const { error } = await supabase
      .from("follow_requests")
      .delete()
      .eq("requester_id", followerId)
      .eq("target_id", targetId)
      .eq("status", "pending")

    if (error) {
      console.error("[follow] cancel request failed", error)
      return { ok: false, message: error.message }
    }

    await removeFollowRequestNotification(supabase, followerId, targetId)
    return { ok: true, state: "none" }
  }

  return { ok: true, state: "none" }
}
