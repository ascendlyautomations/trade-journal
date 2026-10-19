"use client"

import { useMemo, useRef } from "react"
import FeedProfilePostCard from "@/app/components/feed/FeedProfilePostCard"
import type { PendingRoomShareDraft } from "@/lib/roomSharePost"
import { EMPTY_LIKE_META } from "@/app/components/feed/FeedPostCard"

export type CreatePostDraftSnapshot = {
  content: string
  imagePreviewUrl: string | null
  pendingRoomShare: PendingRoomShareDraft | null
}

type CreatePostFeedPreviewProps = {
  draft: CreatePostDraftSnapshot
  userId: string | null
  username: string | null
  avatarUrl: string | null
  user: { id: string } | null
}

export default function CreatePostFeedPreview({
  draft,
  userId,
  username,
  avatarUrl,
  user,
}: CreatePostFeedPreviewProps) {
  const previewCreatedAt = useRef(new Date().toISOString()).current

  const hasContent =
    draft.content.trim().length > 0 ||
    draft.imagePreviewUrl != null ||
    draft.pendingRoomShare != null

  const draftPost = useMemo(() => {
    const share = draft.pendingRoomShare
    return {
      feedKind: "profile" as const,
      id: "create-post-preview",
      user_id: userId ?? "",
      created_at: previewCreatedAt,
      content: draft.content.trim() || null,
      image_url: draft.imagePreviewUrl,
      room_id: share?.roomId ?? null,
      room_name: share?.roomName ?? null,
      room_logo: share?.roomLogo ?? null,
      room_description: share?.roomDescription ?? null,
      profiles: {
        username: username?.trim() || "You",
        avatar_url: avatarUrl,
      },
    }
  }, [
    avatarUrl,
    draft.content,
    draft.imagePreviewUrl,
    draft.pendingRoomShare,
    previewCreatedAt,
    userId,
    username,
  ])

  if (!hasContent) {
    return (
      <div className="rounded-xl border border-dashed border-white/15 bg-white/5 p-6 text-center text-xs text-gray-400">
        Add text, an image, or a room share to see how your post will look in
        the feed.
      </div>
    )
  }

  return (
    <FeedProfilePostCard
      post={draftPost}
      user={user}
      preview
      likeMeta={EMPTY_LIKE_META}
      commentCount={0}
      mediaPriority
    />
  )
}
