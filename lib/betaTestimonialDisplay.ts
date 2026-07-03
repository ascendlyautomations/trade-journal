export type PublicBetaTestimonial = {
  id: string
  rating: number
  title: string
  review: string
  pros: string | null
  cons: string | null
  would_recommend: boolean
  featured: boolean
  created_at: string
  username: string | null
  avatar_url: string | null
  trading_style: string | null
  trader_type: string | null
  started_trading: string | null
}

export function formatTradingExperienceLabel(
  profile: Pick<
    PublicBetaTestimonial,
    "trading_style" | "trader_type" | "started_trading"
  >
): string | null {
  const parts: string[] = []
  if (profile.trading_style?.trim()) parts.push(profile.trading_style.trim())
  if (profile.trader_type?.trim()) parts.push(profile.trader_type.trim())
  if (profile.started_trading?.trim()) {
    parts.push(`Since ${profile.started_trading.trim()}`)
  }
  return parts.length > 0 ? parts.join(" · ") : null
}

export function computeBetaTestimonialStats(rows: PublicBetaTestimonial[]) {
  if (rows.length === 0) {
    return { averageRating: 0, count: 0 }
  }
  const total = rows.reduce((sum, row) => sum + row.rating, 0)
  return {
    averageRating: Math.round((total / rows.length) * 10) / 10,
    count: rows.length,
  }
}

export function selectHomepageTestimonials(
  rows: PublicBetaTestimonial[],
  limit = 3
): PublicBetaTestimonial[] {
  const featured = rows.filter((row) => row.featured)
  if (featured.length >= limit) return featured.slice(0, limit)
  const featuredIds = new Set(featured.map((row) => row.id))
  const remainder = rows.filter((row) => !featuredIds.has(row.id))
  return [...featured, ...remainder].slice(0, limit)
}
