"use client"

import { useCallback, useEffect, useRef, useState, type MouseEvent } from "react"
import { supabase } from "@/lib/supabaseClient"
import {
  followButtonLabel,
  followOrRequest,
  followRelationshipTriggerLabel,
  isMutualFollow,
  loadFollowUiSnapshot,
  unfollowOrCancelRequest,
  type FollowUiState,
} from "@/lib/followActions"
import DropdownMenu, {
  FOLLOW_RELATIONSHIP_FUTURE_MENU_ITEMS,
} from "@/app/components/ui/DropdownMenu"

type FollowButtonProps = {
  targetUserId: string
  currentUserId: string | null
  targetIsPrivate?: boolean | null
  /** When provided, skips per-button follow lookup. */
  followingIds?: Set<string>
  requestedIds?: Set<string>
  /** Profile user ids that follow the current user (reverse edge). */
  followsYouIds?: Set<string>
  onFollowingChange?: (targetUserId: string, following: boolean) => void
  onRequestedChange?: (targetUserId: string, requested: boolean) => void
  className?: string
  stopPropagation?: boolean
}

function stateFromSets(
  targetUserId: string,
  followingIds?: Set<string>,
  requestedIds?: Set<string>
): FollowUiState | null {
  if (followingIds || requestedIds) {
    if (followingIds?.has(targetUserId)) return "following"
    if (requestedIds?.has(targetUserId)) return "requested"
    return "none"
  }
  return null
}

const FOLLOWING_BUTTON_CLASS =
  "shrink-0 rounded-md bg-white/10 px-3 py-1 text-sm font-medium text-white transition hover:bg-white/20 disabled:opacity-50"
const PRIMARY_BUTTON_CLASS =
  "shrink-0 rounded-md bg-blue-500 px-3 py-1 text-sm font-medium text-white transition hover:bg-blue-600 disabled:opacity-50"

export default function FollowButton({
  targetUserId,
  currentUserId,
  targetIsPrivate = false,
  followingIds,
  requestedIds,
  followsYouIds,
  onFollowingChange,
  onRequestedChange,
  className = "",
  stopPropagation = true,
}: FollowButtonProps) {
  const presetState = stateFromSets(targetUserId, followingIds, requestedIds)
  const [followState, setFollowState] = useState<FollowUiState>(
    presetState ?? "none"
  )
  const [followsYou, setFollowsYou] = useState(
    () => followsYouIds?.has(targetUserId) ?? false
  )
  const [busy, setBusy] = useState(false)
  const busyRef = useRef(false)

  useEffect(() => {
    const fromSets = stateFromSets(targetUserId, followingIds, requestedIds)
    if (fromSets != null) {
      setFollowState(fromSets)
      setFollowsYou(followsYouIds?.has(targetUserId) ?? false)
      return
    }

    if (!currentUserId || currentUserId === targetUserId) {
      setFollowState("none")
      setFollowsYou(false)
      return
    }

    let cancelled = false

    void (async () => {
      const snapshot = await loadFollowUiSnapshot(
        supabase,
        currentUserId,
        targetUserId
      )
      if (!cancelled) {
        setFollowState(snapshot.state)
        setFollowsYou(snapshot.followsYou)
      }
    })()

    return () => {
      cancelled = true
    }
  }, [currentUserId, targetUserId, followingIds, requestedIds, followsYouIds])

  const handleUnfollowOrCancel = useCallback(async () => {
    if (!currentUserId || busyRef.current || busy) return

    busyRef.current = true
    setBusy(true)

    try {
    const result = await unfollowOrCancelRequest(
      supabase,
      currentUserId,
      targetUserId,
      followState === "requested" ? "requested" : "following"
    )

    if (!result.ok) {
      console.error("[follow] unfollow/cancel failed", result.message)
      return
    }

    setFollowState(result.state)
    onFollowingChange?.(targetUserId, false)
    onRequestedChange?.(targetUserId, false)
    } finally {
      busyRef.current = false
      setBusy(false)
    }
  }, [
    busy,
    currentUserId,
    followState,
    onFollowingChange,
    onRequestedChange,
    targetUserId,
  ])

  if (!currentUserId || currentUserId === targetUserId) return null

  const mutual = isMutualFollow(followState, followsYou)
  const relationshipLabel = followRelationshipTriggerLabel(followState, followsYou)

  async function handlePrimaryClick(e: MouseEvent<HTMLButtonElement>) {
    if (stopPropagation) e.stopPropagation()
    if (busyRef.current || busy || followState === "following") return

    if (followState === "requested") {
      await handleUnfollowOrCancel()
      return
    }

    busyRef.current = true
    setBusy(true)

    try {
    const result = await followOrRequest(supabase, currentUserId, {
      id: targetUserId,
      is_private: targetIsPrivate,
    })

    if (!result.ok) {
      console.error("[follow] request failed", result.message)
      return
    }

    setFollowState(result.state)
    onFollowingChange?.(targetUserId, result.state === "following")
    onRequestedChange?.(targetUserId, result.state === "requested")
    } finally {
      busyRef.current = false
      setBusy(false)
    }
  }

  if (followState === "following" && relationshipLabel) {
    const statusLabel = mutual ? "Friends ✓" : "Following ✓"

    return (
      <DropdownMenu
        disabled={busy}
        stopPropagation={stopPropagation}
        className={className}
        trigger={
          <span className={`${FOLLOWING_BUTTON_CLASS} inline-flex items-center gap-1`}>
            <span>{relationshipLabel}</span>
            <span className="text-[10px] opacity-80" aria-hidden>
              ▼
            </span>
          </span>
        }
        items={[
          {
            id: "status",
            label: statusLabel,
            disabled: true,
          },
          {
            id: "unfollow",
            label: "Unfollow",
            onSelect: () => void handleUnfollowOrCancel(),
          },
          ...FOLLOW_RELATIONSHIP_FUTURE_MENU_ITEMS,
        ]}
      />
    )
  }

  const label = followButtonLabel(followState, followsYou)
  const buttonClass =
    followState === "requested" ? FOLLOWING_BUTTON_CLASS : PRIMARY_BUTTON_CLASS

  return (
    <button
      type="button"
      onClick={handlePrimaryClick}
      disabled={busy}
      className={`${buttonClass} ${className}`}
    >
      {label}
    </button>
  )
}
