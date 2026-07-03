export type PublicUserReview = {
  id: string
  rating: number
  title: string | null
  review: string
  would_recommend: boolean
  featured: boolean
  created_at: string
  display_name: string | null
  username_snapshot: string | null
  avatar_snapshot: string | null
}

/** Avatar for homepage cards — snapshot first; RPC may include live profile fallback. */
export function resolvePublicReviewAvatar(review: PublicUserReview): string | null {
  const src = review.avatar_snapshot?.trim()
  return src || null
}

export type UserReviewStats = {
  averageRating: number
  count: number
}

export function formatUserReviewDisplayName(review: PublicUserReview): string {
  const name = review.display_name?.trim()
  if (name) return name
  const username = review.username_snapshot?.trim()
  if (username) return username.startsWith("@") ? username.slice(1) : username
  return "TradeTraxs User"
}

export function formatUserReviewUsername(review: PublicUserReview): string | null {
  const username = review.username_snapshot?.trim()
  if (!username) return null
  return username.startsWith("@") ? username : `@${username}`
}

export function computeUserReviewStats(rows: PublicUserReview[]): UserReviewStats {
  if (rows.length === 0) {
    return { averageRating: 0, count: 0 }
  }
  const total = rows.reduce((sum, row) => sum + row.rating, 0)
  return {
    averageRating: Math.round((total / rows.length) * 10) / 10,
    count: rows.length,
  }
}

/** Homepage cards: approved + featured only. */
export function selectFeaturedHomepageReviews(
  rows: PublicUserReview[],
  limit = 3
): PublicUserReview[] {
  return rows
    .filter((row) => row.featured)
    .sort(
      (a, b) =>
        new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
    )
    .slice(0, limit)
}

/** Approved reviews for average rating (excludes pending/rejected at RPC layer). */
export function filterApprovedForStats(rows: PublicUserReview[]): PublicUserReview[] {
  return rows
}
