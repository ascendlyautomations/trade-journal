import type { ExploreProfile, TraderTradeMeta } from "@/lib/exploreDiscover"
import { normalizeTraderType, type TraderType } from "@/lib/traderType"
import type { DashboardSessionBucket } from "@/lib/dashboardSessionBuckets"
import { normalizeSessionBucket } from "@/lib/dashboardSessionBuckets"

export type ExploreCategoryTab = "all" | "futures" | "options" | "investing"

export type ExploreSessionFilter = "all" | DashboardSessionBucket

export type ExploreExperienceFilter =
  | "all"
  | "beginner"
  | "intermediate"
  | "advanced"

export type ExploreTradingStyleFilter =
  | "all"
  | "scalper"
  | "day_trader"
  | "swing_trader"
  | "position_trader"

export type ExploreMarketFilter =
  | "all"
  | "nq"
  | "es"
  | "spy"
  | "qqq"
  | "stocks"
  | "crypto"
  | "forex"

export type ExploreDiscoverFilters = {
  category: ExploreCategoryTab
  session: ExploreSessionFilter
  experience: ExploreExperienceFilter
  tradingStyle: ExploreTradingStyleFilter
  market: ExploreMarketFilter
}

export const EXPLORE_DEFAULT_FILTERS: ExploreDiscoverFilters = {
  category: "all",
  session: "all",
  experience: "all",
  tradingStyle: "all",
  market: "all",
}

export const EXPLORE_CATEGORY_TABS: ReadonlyArray<{
  value: ExploreCategoryTab
  label: string
}> = [
  { value: "all", label: "All" },
  { value: "futures", label: "Futures" },
  { value: "options", label: "Options" },
  { value: "investing", label: "Investing" },
]

export function categoryTabFromTraderType(
  traderType: string | null | undefined
): ExploreCategoryTab {
  const normalized = normalizeTraderType(traderType)
  if (normalized === "Futures") return "futures"
  if (normalized === "Options") return "options"
  if (normalized === "Investor") return "investing"
  return "all"
}

export function profileMatchesCategoryTab(
  profile: Pick<ExploreProfile, "trader_type">,
  tab: ExploreCategoryTab
): boolean {
  if (tab === "all") return true
  const type = normalizeTraderType(profile.trader_type)
  if (tab === "futures") return type === "Futures"
  if (tab === "options") return type === "Options"
  if (tab === "investing") return type === "Investor"
  return true
}

export function normalizeTradingStyleCategory(
  style: string | null | undefined
): Exclude<ExploreTradingStyleFilter, "all"> | null {
  const s = String(style ?? "").toLowerCase()
  if (!s) return null
  if (s.includes("scalp")) return "scalper"
  if (s.includes("day") || s.includes("intraday")) return "day_trader"
  if (s.includes("swing")) return "swing_trader"
  if (
    s.includes("position") ||
    s.includes("invest") ||
    s.includes("long term") ||
    s.includes("long-term")
  ) {
    return "position_trader"
  }
  return null
}

export function experienceLevelFromStartedTrading(
  startedTrading: string | null | undefined,
  now = Date.now()
): Exclude<ExploreExperienceFilter, "all"> | null {
  if (!startedTrading) return null
  const start = new Date(startedTrading)
  if (Number.isNaN(start.getTime())) return null

  const months =
    (new Date(now).getFullYear() - start.getFullYear()) * 12 +
    (new Date(now).getMonth() - start.getMonth())

  if (months < 12) return "beginner"
  if (months < 36) return "intermediate"
  return "advanced"
}

const MARKET_TICKER_PATTERNS: Record<
  Exclude<ExploreMarketFilter, "all">,
  RegExp
> = {
  nq: /\b(nq|mnq|nasdaq)\b/i,
  es: /\b(es|mes|s&p|sp500)\b/i,
  spy: /\bspy\b/i,
  qqq: /\bqqq\b/i,
  stocks: /\b(stock|equity|equities|shares)\b/i,
  crypto: /\b(btc|eth|crypto|bitcoin|ethereum)\b/i,
  forex: /\b(forex|fx|eur|gbp|usd\/|\/usd)\b/i,
}

function textMatchesMarketFilter(
  text: string,
  filter: Exclude<ExploreMarketFilter, "all">
): boolean {
  return MARKET_TICKER_PATTERNS[filter].test(text)
}

export function profileMatchesMarketFilter(
  profile: Pick<ExploreProfile, "primary_market">,
  tradeMeta: TraderTradeMeta | undefined,
  filter: ExploreMarketFilter
): boolean {
  if (filter === "all") return true

  const marketText = String(profile.primary_market ?? "").trim()
  if (marketText && textMatchesMarketFilter(marketText, filter)) return true

  const symbols = tradeMeta?.topSymbols ?? []
  return symbols.some((symbol) => textMatchesMarketFilter(symbol, filter))
}

export function profileMatchesDiscoverFilters(
  profile: ExploreProfile,
  filters: ExploreDiscoverFilters,
  tradeMeta?: TraderTradeMeta
): boolean {
  if (!profileMatchesCategoryTab(profile, filters.category)) return false

  if (filters.session !== "all") {
    const session = tradeMeta?.dominantSession ?? null
    if (!session || session !== filters.session) return false
  }

  if (filters.experience !== "all") {
    const level = experienceLevelFromStartedTrading(profile.started_trading)
    if (!level || level !== filters.experience) return false
  }

  if (filters.tradingStyle !== "all") {
    const style = normalizeTradingStyleCategory(
      profile.trading_style || profile.trading_model
    )
    if (!style || style !== filters.tradingStyle) return false
  }

  if (filters.market !== "all") {
    if (!profileMatchesMarketFilter(profile, tradeMeta, filters.market)) {
      return false
    }
  }

  return true
}

export function filterExploreProfiles(
  profiles: ExploreProfile[],
  filters: ExploreDiscoverFilters,
  tradeMetaByUserId: Record<string, TraderTradeMeta>
): ExploreProfile[] {
  return profiles.filter((profile) =>
    profileMatchesDiscoverFilters(
      profile,
      filters,
      tradeMetaByUserId[profile.id]
    )
  )
}

export function discoverFilterAvailability(args: {
  profiles: ExploreProfile[]
  tradeMetaByUserId: Record<string, TraderTradeMeta>
}): {
  session: boolean
  experience: boolean
  tradingStyle: boolean
} {
  const { profiles, tradeMetaByUserId } = args

  let session = false
  let experience = false
  let tradingStyle = false

  for (const profile of profiles) {
    const meta = tradeMetaByUserId[profile.id]
    if (meta?.dominantSession) session = true
    if (experienceLevelFromStartedTrading(profile.started_trading)) {
      experience = true
    }
    if (
      normalizeTradingStyleCategory(
        profile.trading_style || profile.trading_model
      )
    ) {
      tradingStyle = true
    }
  }

  return { session, experience, tradingStyle }
}

export function traderTypeSectionLabel(type: TraderType): string {
  if (type === "Futures") return "Futures Traders"
  if (type === "Options") return "Options Traders"
  return "Investors"
}
