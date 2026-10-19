import type { VaultContentRef } from "./types"

/** Profile browse cards hide Vault on the viewer's own profile (native iOS parity). */
export function profileEngagementVaultRef(
  ref: VaultContentRef,
  profileUserId: string,
  viewerUserId: string | null | undefined
): VaultContentRef | null {
  if (!viewerUserId || viewerUserId === profileUserId) return null
  return ref
}

export function vaultRefFromFeedItem(post: {
  id: string
  feedKind?: string
  achievement_id?: string | null
  achievements?: { id?: string } | null
}): VaultContentRef | null {
  const id = String(post.id)
  switch (post.feedKind) {
    case "profile":
      return { contentType: "profile_post", contentID: id }
    case "reel":
      return { contentType: "reel", contentID: id }
    case "achievement": {
      const achId =
        post.achievements?.id != null
          ? String(post.achievements.id)
          : post.achievement_id != null
            ? String(post.achievement_id)
            : ""
      return achId ? { contentType: "achievement", contentID: achId } : null
    }
    case "trade":
      return { contentType: "feed_post", contentID: id }
    default:
      return { contentType: "feed_post", contentID: id }
  }
}
