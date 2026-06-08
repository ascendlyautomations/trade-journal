"use client"

import { useEffect, useState, type MouseEvent } from "react"
import { supabase } from "@/lib/supabaseClient"

type FollowButtonProps = {
  targetUserId: string
  currentUserId: string | null
  /** When provided, skips per-button follow lookup. */
  followingIds?: Set<string>
  onFollowingChange?: (targetUserId: string, following: boolean) => void
  className?: string
  stopPropagation?: boolean
}

export default function FollowButton({
  targetUserId,
  currentUserId,
  followingIds,
  onFollowingChange,
  className = "",
  stopPropagation = true,
}: FollowButtonProps) {
  const [isFollowing, setIsFollowing] = useState(
    () => followingIds?.has(targetUserId) ?? false
  )
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    if (followingIds) {
      setIsFollowing(followingIds.has(targetUserId))
      return
    }

    if (!currentUserId || currentUserId === targetUserId) {
      setIsFollowing(false)
      return
    }

    let cancelled = false

    async function loadFollowState() {
      const { data } = await supabase
        .from("followers")
        .select("following_id")
        .eq("follower_id", currentUserId)
        .eq("following_id", targetUserId)
        .maybeSingle()

      if (!cancelled) setIsFollowing(!!data)
    }

    void loadFollowState()
    return () => {
      cancelled = true
    }
  }, [currentUserId, targetUserId, followingIds])

  if (!currentUserId || currentUserId === targetUserId) return null

  async function handleClick(e: MouseEvent<HTMLButtonElement>) {
    if (stopPropagation) e.stopPropagation()
    if (busy) return

    setBusy(true)

    if (isFollowing) {
      await supabase
        .from("followers")
        .delete()
        .eq("follower_id", currentUserId)
        .eq("following_id", targetUserId)
      setIsFollowing(false)
      onFollowingChange?.(targetUserId, false)
    } else {
      await supabase.from("followers").insert({
        follower_id: currentUserId,
        following_id: targetUserId,
      })
      setIsFollowing(true)
      onFollowingChange?.(targetUserId, true)
    }

    setBusy(false)
  }

  return (
    <button
      type="button"
      onClick={handleClick}
      disabled={busy}
      className={`shrink-0 rounded-md px-3 py-1 text-sm font-medium text-white transition disabled:opacity-50 ${
        isFollowing
          ? "bg-white/10 hover:bg-white/20"
          : "bg-blue-500 hover:bg-blue-600"
      } ${className}`}
    >
      {isFollowing ? "Following" : "Follow"}
    </button>
  )
}
