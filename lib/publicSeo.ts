import type { Metadata } from "next"
import { isProfileUuidSegment } from "@/lib/profileRoutes"
import { normalizeProfileUsername } from "@/lib/profileUsername"
import { createSupabaseAdmin } from "@/lib/supabaseAdmin"
import { DEFAULT_OG_IMAGE_PATH, SITE_NAME, SITE_URL } from "@/lib/site"

const PROFILE_SEO_SELECT = "id, username, name, is_private, created_at" as const
const TRADE_SEO_SELECT = "id, ticker, is_public, user_id, created_at" as const
const SITEMAP_PROFILE_LIMIT = 10_000
const SITEMAP_TRADE_LIMIT = 50_000

export type ProfileSeoData = {
  id: string
  username: string | null
  name: string | null
  is_private: boolean | null
  created_at: string | null
}

export type TradeSeoData = {
  id: string
  ticker: string | null
  is_public: boolean | null
  user_id: string | null
  created_at: string | null
}

export type TradeOwnerSeoData = {
  name: string | null
  username: string | null
}

export function profileSeoDisplayName(profile: {
  username?: string | null
  name?: string | null
}): string {
  const name = String(profile.name ?? "").trim()
  if (name) return name
  const username = normalizeProfileUsername(profile.username ?? "")
  if (username) return username
  return "Trader"
}

export function profileCanonicalPath(profile: {
  username?: string | null
}): string | null {
  const username = normalizeProfileUsername(profile.username ?? "")
  if (!username) return null
  return `/profile/${username}`
}

export function isPublicProfileForIndexing(profile: {
  username?: string | null
  is_private?: boolean | null
}): boolean {
  if (profile.is_private === true) return false
  return normalizeProfileUsername(profile.username ?? "").length > 0
}

export async function fetchProfileForSeo(
  segment: string
): Promise<ProfileSeoData | null> {
  const admin = createSupabaseAdmin()
  if (!admin) return null

  const trimmed = segment.trim()
  if (!trimmed) return null

  let query = admin.from("profiles").select(PROFILE_SEO_SELECT)
  if (isProfileUuidSegment(trimmed)) {
    query = query.eq("id", trimmed)
  } else {
    query = query.eq("username", normalizeProfileUsername(trimmed))
  }

  const { data, error } = await query.maybeSingle()
  if (error || !data) return null
  return data
}

export async function fetchTradeForSeo(
  tradeId: string
): Promise<{ trade: TradeSeoData; owner: TradeOwnerSeoData | null } | null> {
  const admin = createSupabaseAdmin()
  if (!admin) return null

  const id = tradeId.trim()
  if (!id) return null

  const { data: trade, error } = await admin
    .from("trades")
    .select(TRADE_SEO_SELECT)
    .eq("id", id)
    .maybeSingle()

  if (error || !trade) return null

  let owner: TradeOwnerSeoData | null = null
  if (trade.user_id) {
    const { data: profile } = await admin
      .from("profiles")
      .select("name, username")
      .eq("id", trade.user_id)
      .maybeSingle()
    owner = profile ?? null
  }

  return { trade, owner }
}

export function buildProfileMetadata(profile: ProfileSeoData | null): Metadata {
  if (!profile) {
    return {
      title: { absolute: `Profile Not Found | ${SITE_NAME}` },
      description: "This profile could not be found on TradeTraxs.",
      robots: { index: false, follow: false },
    }
  }

  const displayName = profileSeoDisplayName(profile)
  const indexable = isPublicProfileForIndexing(profile)
  const canonicalPath = profileCanonicalPath(profile)

  const title = `${displayName} | Trader Profile | ${SITE_NAME}`
  const description = `View ${displayName}'s public trading profile, statistics, and trade history on ${SITE_NAME}.`
  const ogTitle = `${displayName} | ${SITE_NAME}`
  const ogDescription = "View public trading performance and trade history."

  const metadata: Metadata = {
    title: { absolute: title },
    description,
    openGraph: {
      type: "profile",
      title: ogTitle,
      description: ogDescription,
      siteName: SITE_NAME,
      images: [{ url: DEFAULT_OG_IMAGE_PATH, alt: SITE_NAME }],
      ...(canonicalPath ? { url: `${SITE_URL}${canonicalPath}` } : {}),
    },
    twitter: {
      card: "summary_large_image",
      title: ogTitle,
      description: ogDescription,
      images: [DEFAULT_OG_IMAGE_PATH],
    },
  }

  if (indexable && canonicalPath) {
    metadata.alternates = { canonical: canonicalPath }
  } else {
    metadata.robots = { index: false, follow: false }
  }

  return metadata
}

export function buildTradeMetadata(
  trade: TradeSeoData | null,
  owner: TradeOwnerSeoData | null
): Metadata {
  if (!trade || trade.is_public !== true) {
    return {
      title: { absolute: `Trade | ${SITE_NAME}` },
      description: "This trade is not publicly available on TradeTraxs.",
      robots: { index: false, follow: false },
    }
  }

  const ticker = String(trade.ticker ?? "").trim() || "Trade"
  const displayName = owner ? profileSeoDisplayName(owner) : "Trader"
  const title = `${ticker} Trade by ${displayName} | ${SITE_NAME}`
  const description =
    "View a public trade shared on TradeTraxs including performance, screenshots, and analysis."
  const canonicalPath = `/trade/${trade.id}`

  return {
    title: { absolute: title },
    description,
    alternates: { canonical: canonicalPath },
    openGraph: {
      type: "article",
      url: `${SITE_URL}${canonicalPath}`,
      title,
      description,
      siteName: SITE_NAME,
      images: [{ url: DEFAULT_OG_IMAGE_PATH, alt: SITE_NAME }],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: [DEFAULT_OG_IMAGE_PATH],
    },
  }
}

export async function fetchPublicProfilesForSitemap(): Promise<
  Array<{ path: string; lastModified: Date }>
> {
  const admin = createSupabaseAdmin()
  if (!admin) return []

  const { data, error } = await admin
    .from("profiles")
    .select("username, created_at")
    .neq("is_private", true)
    .not("username", "is", null)
    .limit(SITEMAP_PROFILE_LIMIT)

  if (error || !data) return []

  return data
    .filter((row) => isPublicProfileForIndexing(row))
    .map((row) => ({
      path: `/profile/${normalizeProfileUsername(row.username!)}`,
      lastModified: row.created_at ? new Date(row.created_at) : new Date(),
    }))
}

export async function fetchPublicTradesForSitemap(): Promise<
  Array<{ path: string; lastModified: Date }>
> {
  const admin = createSupabaseAdmin()
  if (!admin) return []

  const { data, error } = await admin
    .from("trades")
    .select("id, created_at")
    .eq("is_public", true)
    .limit(SITEMAP_TRADE_LIMIT)

  if (error || !data) return []

  return data.map((row) => ({
    path: `/trade/${row.id}`,
    lastModified: row.created_at ? new Date(row.created_at) : new Date(),
  }))
}
