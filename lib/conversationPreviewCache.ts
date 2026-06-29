export function dmTradePreviewCacheKey(
  tradeId: string | null | undefined
): string | null {
  const id = tradeId != null ? String(tradeId).trim() : ""
  return id ? `trade:${id}` : null
}

export function dmPostPreviewCacheKey(message: {
  type?: string | null
  post_id?: string | null
  profile_post_id?: string | null
  achievement_post_id?: string | null
  reel_id?: string | null
}): string | null {
  const isReelShare =
    message.type === "reel" || Boolean(message.reel_id)
  if (isReelShare) {
    const id =
      message.reel_id != null ? String(message.reel_id).trim() : ""
    return id ? `reel:${id}` : null
  }
  const isAchievementShare =
    message.type === "achievement_post" || Boolean(message.achievement_post_id)
  if (isAchievementShare) {
    const id =
      message.achievement_post_id != null
        ? String(message.achievement_post_id).trim()
        : ""
    return id ? `achievement_post:${id}` : null
  }
  const isProfileShare =
    message.type === "profile_post" || Boolean(message.profile_post_id)
  if (isProfileShare) {
    const id =
      message.profile_post_id != null
        ? String(message.profile_post_id).trim()
        : ""
    return id ? `profile_post:${id}` : null
  }
  if (message.type === "post" || message.post_id) {
    const id = message.post_id != null ? String(message.post_id).trim() : ""
    return id ? `post:${id}` : null
  }
  return null
}
