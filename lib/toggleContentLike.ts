/**
 * Optimistic like toggle for trade posts, profile posts, and achievement posts.
 * Mirrors toggleReelLike — UI first, rollback on failure (except 23505).
 */

import type { SupabaseClient } from "@supabase/supabase-js"
import { hapticLight } from "@/lib/nativeHaptics"
import {
  likeMetaAfterConflict,
  nextLikeMeta,
  UNIQUE_VIOLATION,
  type LikeMeta,
} from "@/lib/optimisticMutation"
import {
  deleteLikeNotification,
  ensureLikeNotification,
} from "@/lib/likeNotifications"

export type ContentLikeKind = "post" | "profile_post" | "achievement_post" | "trade"

export type ContentLikeMeta = LikeMeta

export async function toggleContentLike(
  client: SupabaseClient,
  params: {
    kind: ContentLikeKind
    contentId: string
    userId: string
    ownerUserId: string | null
    meta: ContentLikeMeta
    /** Required for kind === "post" (trade-linked feed post). */
    tradeId?: string | null
    onMetaChange: (next: ContentLikeMeta) => void
  }
): Promise<boolean> {
  const contentId = params.contentId.trim()
  const { kind, userId, ownerUserId, meta, tradeId, onMetaChange } = params
  if (!contentId || !userId) return false

  const optimistic = nextLikeMeta(meta)
  onMetaChange(optimistic)
  hapticLight("like")

  try {
    if (meta.liked) {
      const { error } =
        kind === "profile_post"
          ? await client
              .from("profile_post_likes")
              .delete()
              .eq("profile_post_id", contentId)
              .eq("user_id", userId)
          : kind === "achievement_post"
            ? await client
                .from("achievement_post_likes")
                .delete()
                .eq("achievement_post_id", contentId)
                .eq("user_id", userId)
            : kind === "trade"
              ? await client
                  .from("trade_likes")
                  .delete()
                  .eq("trade_id", contentId)
                  .eq("user_id", userId)
              : await client
                  .from("likes")
                  .delete()
                  .eq("post_id", contentId)
                  .eq("user_id", userId)

      if (error) {
        console.error(`[${kind}-like] unlike failed`, error)
        onMetaChange(meta)
        return false
      }

      if (ownerUserId) {
        await deleteLikeNotification(client, {
          recipientUserId: String(ownerUserId),
          senderUserId: userId,
          target:
            kind === "profile_post"
              ? { kind: "profile_post", profilePostId: contentId }
              : kind === "achievement_post"
                ? { kind: "achievement_post", achievementPostId: contentId }
                : kind === "trade"
                  ? { kind: "trade", tradeId: contentId }
                  : {
                      kind: "post",
                      postId: contentId,
                      tradeId: tradeId ?? null,
                    },
        })
      }

      return true
    }

    const { error } =
      kind === "profile_post"
        ? await client.from("profile_post_likes").insert({
            profile_post_id: contentId,
            user_id: userId,
          })
        : kind === "achievement_post"
          ? await client.from("achievement_post_likes").insert({
              achievement_post_id: contentId,
              user_id: userId,
            })
          : kind === "trade"
            ? await client.from("trade_likes").insert({
                trade_id: contentId,
                user_id: userId,
              })
            : await client.from("likes").insert({
                post_id: contentId,
                user_id: userId,
              })

    if (error?.code === UNIQUE_VIOLATION) {
      onMetaChange(likeMetaAfterConflict(meta))
      return true
    }

    if (error) {
      console.error(`[${kind}-like] insert failed`, error)
      onMetaChange(meta)
      return false
    }

    if (ownerUserId && ownerUserId !== userId) {
      await ensureLikeNotification(client, {
        recipientUserId: String(ownerUserId),
        senderUserId: userId,
        target:
          kind === "profile_post"
            ? { kind: "profile_post", profilePostId: contentId }
            : kind === "achievement_post"
              ? { kind: "achievement_post", achievementPostId: contentId }
              : kind === "trade"
                ? { kind: "trade", tradeId: contentId }
                : {
                    kind: "post",
                    postId: contentId,
                    tradeId: tradeId ?? null,
                  },
      })
    }

    return true
  } catch (err) {
    console.error(`[${kind}-like] toggle failed`, err)
    onMetaChange(meta)
    return false
  }
}
