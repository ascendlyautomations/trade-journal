export type AchievementTier = "bronze" | "silver" | "gold" | "platinum" | string

/** Canonical achievement_type values stored in the database. */
export const ACHIEVEMENT_TYPE = {
  PROP_FIRM_PAYOUT: "prop_firm_payout",
  LIVE_TRADING_PAYOUT: "live_trading_payout",
  PASSED_EVAL: "passed_eval",
  MILESTONE: "milestone",
  /** @deprecated Legacy generic payout — migrated on read/save. */
  LEGACY_PAYOUT: "payout",
} as const

export type AchievementType =
  | typeof ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT
  | typeof ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT
  | typeof ACHIEVEMENT_TYPE.PASSED_EVAL
  | typeof ACHIEVEMENT_TYPE.MILESTONE
  | typeof ACHIEVEMENT_TYPE.LEGACY_PAYOUT

export type AchievementCategory =
  | "prop_firm_payouts"
  | "live_trading_payouts"
  | "passed_evals"
  | "milestones"
  /** @deprecated Legacy bucket — still matches the payouts filter. */
  | "payouts"
  | string

export type AchievementCategoryFilter =
  | "all"
  | "payouts"
  | "passed_evals"
  | "milestones"

/** Page filter for achievement types (restored alongside track/category filter). */
export type AchievementTypeFilter =
  | "all"
  | "prop_firm_payout"
  | "live_trading_payout"
  | "passed_evals"
  | "milestones"

export const ACHIEVEMENT_TYPE_FILTER_OPTIONS: ReadonlyArray<{
  value: AchievementTypeFilter
  label: string
}> = [
  { value: "all", label: "All" },
  { value: "prop_firm_payout", label: "Prop Firm Payout" },
  { value: "live_trading_payout", label: "Live Trading Payout" },
  { value: "passed_evals", label: "Passed Evals" },
  { value: "milestones", label: "Milestones" },
]

/** High-level achievement track for page filters and future expansion. */
export type AchievementTrack =
  | "prop_firm"
  | "live_trading"
  | "general"
  | "community"

export type AchievementTrackFilter = "all" | "prop_firm" | "live_trading"

export const ACHIEVEMENT_TRACK_FILTER_OPTIONS: ReadonlyArray<{
  value: AchievementTrackFilter
  label: string
}> = [
  { value: "all", label: "All" },
  { value: "prop_firm", label: "Prop Firm" },
  { value: "live_trading", label: "Live Trading" },
]

/** Map canonical achievement types (and future prefixes) to a track. */
export function achievementTrackFromType(
  type: string | null | undefined
): AchievementTrack {
  const raw = String(type ?? "")
    .trim()
    .toLowerCase()
  const canonical = canonicalAchievementType(type)

  if (
    canonical === ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT ||
    canonical === ACHIEVEMENT_TYPE.PASSED_EVAL ||
    raw.startsWith("prop_firm")
  ) {
    return "prop_firm"
  }

  if (
    canonical === ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT ||
    raw.startsWith("live_trading")
  ) {
    return "live_trading"
  }

  if (raw.startsWith("community")) {
    return "community"
  }

  return "general"
}

export function achievementMatchesTrackFilter(
  achievement: Pick<Achievement, "achievement_type">,
  filter: AchievementTrackFilter
): boolean {
  if (filter === "all") return true
  return achievementTrackFromType(achievement.achievement_type) === filter
}

export type Achievement = {
  id: string
  user_id: string
  achievement_type: string
  title: string
  description: string | null
  badge_key: string | null
  tier: AchievementTier | null
  category: AchievementCategory | null
  value_numeric: number | null
  value_text: string | null
  currency: string | null
  account_type: string | null
  account_name: string | null
  account_size: string | null
  mode: string | null
  firm: string | null
  image_url: string | null
  achieved_at: string | null
  created_at: string
  updated_at: string
  is_featured: boolean
  is_public: boolean
  sort_order: number | null
  metadata: Record<string, unknown> | null
}

export const ACHIEVEMENT_SELECT = `
  id,
  user_id,
  achievement_type,
  title,
  description,
  badge_key,
  tier,
  category,
  value_numeric,
  value_text,
  currency,
  account_type,
  account_name,
  account_size,
  mode,
  firm,
  image_url,
  achieved_at,
  created_at,
  updated_at,
  is_featured,
  is_public,
  sort_order,
  metadata
`

/** Public profile achievements — no account_name or account_size. */
export const PUBLIC_ACHIEVEMENT_SELECT = `
  id,
  user_id,
  achievement_type,
  title,
  description,
  badge_key,
  tier,
  category,
  value_numeric,
  value_text,
  currency,
  account_type,
  mode,
  firm,
  image_url,
  achieved_at,
  created_at,
  updated_at,
  is_featured,
  is_public,
  sort_order,
  metadata
`

export const ACHIEVEMENT_TYPE_OPTIONS: ReadonlyArray<{
  value: AchievementType
  label: string
}> = [
  { value: ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT, label: "Prop Firm Payout" },
  { value: ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT, label: "Live Trading Payout" },
  { value: ACHIEVEMENT_TYPE.PASSED_EVAL, label: "Passed Eval" },
  { value: ACHIEVEMENT_TYPE.MILESTONE, label: "Milestone" },
]

/** Normalize stored types to canonical values (legacy `payout` → live trading). */
export function canonicalAchievementType(
  type: string | null | undefined
): AchievementType {
  const t = String(type ?? "")
    .trim()
    .toLowerCase()

  if (t === ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT) {
    return ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT
  }
  if (t === ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT) {
    return ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT
  }
  if (t === ACHIEVEMENT_TYPE.PASSED_EVAL || t === "passed_evals") {
    return ACHIEVEMENT_TYPE.PASSED_EVAL
  }
  if (t === ACHIEVEMENT_TYPE.MILESTONE || t === "milestones") {
    return ACHIEVEMENT_TYPE.MILESTONE
  }
  if (t === ACHIEVEMENT_TYPE.LEGACY_PAYOUT) {
    return ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT
  }
  if (t.includes("payout")) {
    return ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT
  }

  return ACHIEVEMENT_TYPE.MILESTONE
}

/**
 * @deprecated Use {@link canonicalAchievementType} for storage and
 * {@link isPayoutAchievementType} for payout checks.
 */
export function normalizeAchievementType(
  type: string | null
): AchievementType {
  return canonicalAchievementType(type)
}

export function isPropFirmPayoutAchievementType(
  type: string | null | undefined
): boolean {
  return canonicalAchievementType(type) === ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT
}

export function isLiveTradingPayoutAchievementType(
  type: string | null | undefined
): boolean {
  const canonical = canonicalAchievementType(type)
  return (
    canonical === ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT &&
    String(type ?? "")
      .trim()
      .toLowerCase() !== ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT
  )
}

export function isPayoutAchievementType(
  type: string | null | undefined
): boolean {
  const canonical = canonicalAchievementType(type)
  return (
    canonical === ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT ||
    canonical === ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT ||
    String(type ?? "")
      .trim()
      .toLowerCase() === ACHIEVEMENT_TYPE.LEGACY_PAYOUT
  )
}

export function categoryFromType(type: string | null): AchievementCategory {
  const canonical = canonicalAchievementType(type)
  if (canonical === ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT) {
    return "prop_firm_payouts"
  }
  if (canonical === ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT) {
    return "live_trading_payouts"
  }
  if (canonical === ACHIEVEMENT_TYPE.PASSED_EVAL) {
    return "passed_evals"
  }
  return "milestones"
}

export function badgeKeyFromType(type: string | null): string {
  return canonicalAchievementType(type)
}

export function achievementTypeLabel(type: string | null): string {
  const canonical = canonicalAchievementType(type)
  if (canonical === ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT) {
    return "Prop Firm Payout"
  }
  if (canonical === ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT) {
    return "Live Trading Payout"
  }
  if (canonical === ACHIEVEMENT_TYPE.PASSED_EVAL) {
    return "Passed Eval"
  }
  return "Milestone"
}

export function achievementMatchesCategoryFilter(
  achievement: Pick<Achievement, "achievement_type" | "category">,
  filter: AchievementCategoryFilter
): boolean {
  if (filter === "all") return true

  const stored = String(achievement.category ?? "")
    .trim()
    .toLowerCase()
  const derived = String(categoryFromType(achievement.achievement_type))
    .trim()
    .toLowerCase()
  const bucket = stored || derived

  if (filter === "payouts") {
    return (
      isPayoutAchievementType(achievement.achievement_type) ||
      bucket === "payouts" ||
      bucket === "prop_firm_payouts" ||
      bucket === "live_trading_payouts"
    )
  }

  if (filter === "passed_evals") {
    return bucket === "passed_evals"
  }

  if (filter === "milestones") {
    return bucket === "milestones"
  }

  return false
}

export function achievementMatchesTypeFilter(
  achievement: Pick<Achievement, "achievement_type" | "category">,
  filter: AchievementTypeFilter
): boolean {
  if (filter === "all") return true

  const stored = String(achievement.category ?? "")
    .trim()
    .toLowerCase()
  const derived = String(categoryFromType(achievement.achievement_type))
    .trim()
    .toLowerCase()
  const bucket = stored || derived
  const canonical = canonicalAchievementType(achievement.achievement_type)
  const rawType = String(achievement.achievement_type ?? "")
    .trim()
    .toLowerCase()

  if (filter === "prop_firm_payout") {
    return (
      canonical === ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT ||
      bucket === "prop_firm_payouts"
    )
  }

  if (filter === "live_trading_payout") {
    return (
      canonical === ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT ||
      bucket === "live_trading_payouts" ||
      bucket === "payouts" ||
      rawType === ACHIEVEMENT_TYPE.LEGACY_PAYOUT
    )
  }

  if (filter === "passed_evals") {
    return (
      canonical === ACHIEVEMENT_TYPE.PASSED_EVAL || bucket === "passed_evals"
    )
  }

  if (filter === "milestones") {
    return canonical === ACHIEVEMENT_TYPE.MILESTONE || bucket === "milestones"
  }

  return false
}

export function badgeIconForKey(
  badgeKey: string | null,
  achievementType?: string | null
): string {
  const key = String(badgeKey || "")
    .trim()
    .toLowerCase()
  const canonical = canonicalAchievementType(achievementType ?? null)

  if (key.includes("prop_firm") && key.includes("payout")) return "💰"
  if (key.includes("live") && key.includes("payout")) return "💵"
  if (key.includes("payout")) return "💰"
  if (key.includes("eval") || key.includes("pass")) return "✅"
  if (key.includes("milestone")) return "🏆"
  if (canonical === ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT) return "💰"
  if (canonical === ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT) return "💵"
  if (canonical === ACHIEVEMENT_TYPE.PASSED_EVAL) return "✅"
  if (canonical === ACHIEVEMENT_TYPE.MILESTONE) return "🏆"
  return "⭐"
}

export function tierClassName(tier: string | null): string {
  const t = String(tier || "").toLowerCase()
  if (t === "platinum") return "border-cyan-300/40 bg-cyan-500/10"
  if (t === "gold") return "border-amber-300/40 bg-amber-500/10"
  if (t === "silver") return "border-slate-300/40 bg-slate-400/10"
  if (t === "bronze") return "border-orange-300/40 bg-orange-500/10"
  return "border-white/10 bg-white/5"
}

export function formatAchievementDate(value: string | null): string {
  if (!value) return "—"
  const d = new Date(value)
  if (Number.isNaN(d.getTime())) return "—"
  return d.toLocaleDateString()
}

type PayoutAchievementSumInput = {
  achievement_type: string | null
  value_numeric: number | null
}

/** Sum payout achievement values — matches profile overview “Payout Total”. */
export function sumPayoutAchievementTotals(
  achievements: PayoutAchievementSumInput[]
): number {
  return achievements
    .filter((a) => isPayoutAchievementType(a.achievement_type))
    .reduce((sum, a) => sum + (Number(a.value_numeric) || 0), 0)
}

export type PayoutAchievementRow = {
  user_id: string
  achievement_type: string | null
  value_numeric: number | null
}

export function buildPayoutTotalsByUserId(
  rows: PayoutAchievementRow[]
): Record<string, number> {
  const grouped = new Map<string, PayoutAchievementSumInput[]>()

  for (const row of rows) {
    const userId = String(row.user_id ?? "").trim()
    if (!userId) continue
    const list = grouped.get(userId) ?? []
    list.push(row)
    grouped.set(userId, list)
  }

  const totals: Record<string, number> = {}
  for (const [userId, list] of grouped) {
    totals[userId] = sumPayoutAchievementTotals(list)
  }
  return totals
}
