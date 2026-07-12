import type { MetadataRoute } from "next"
import {
  fetchPublicProfilesForSitemap,
  fetchPublicTradesForSitemap,
} from "@/lib/publicSeo"
import { SITE_URL } from "@/lib/site"

const STATIC_PATHS: Array<{
  path: string
  changeFrequency: MetadataRoute.Sitemap[number]["changeFrequency"]
  priority: number
}> = [
  { path: "/", changeFrequency: "weekly", priority: 1 },
  { path: "/pricing", changeFrequency: "monthly", priority: 0.95 },
  { path: "/faq", changeFrequency: "monthly", priority: 0.9 },
  { path: "/about", changeFrequency: "monthly", priority: 0.85 },
  { path: "/contact", changeFrequency: "monthly", priority: 0.75 },
  { path: "/affiliate", changeFrequency: "monthly", priority: 0.8 },
  { path: "/explore", changeFrequency: "daily", priority: 0.9 },
  { path: "/leaderboard", changeFrequency: "daily", priority: 0.9 },
  { path: "/demo", changeFrequency: "monthly", priority: 0.85 },
  { path: "/help", changeFrequency: "monthly", priority: 0.65 },
  { path: "/legal", changeFrequency: "yearly", priority: 0.5 },
  { path: "/privacy", changeFrequency: "yearly", priority: 0.5 },
  { path: "/terms", changeFrequency: "yearly", priority: 0.5 },
  { path: "/refund-policy", changeFrequency: "yearly", priority: 0.5 },
  { path: "/cookie-policy", changeFrequency: "yearly", priority: 0.45 },
  { path: "/acceptable-use", changeFrequency: "yearly", priority: 0.45 },
  { path: "/copyright", changeFrequency: "yearly", priority: 0.45 },
  { path: "/community-guidelines", changeFrequency: "yearly", priority: 0.45 },
  { path: "/creator-guidelines", changeFrequency: "yearly", priority: 0.45 },
]

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const lastModified = new Date()

  const staticEntries: MetadataRoute.Sitemap = STATIC_PATHS.map(
    ({ path, changeFrequency, priority }) => ({
      url: `${SITE_URL}${path === "/" ? "" : path}`,
      lastModified,
      changeFrequency,
      priority,
    })
  )

  const [publicProfiles, publicTrades] = await Promise.all([
    fetchPublicProfilesForSitemap(),
    fetchPublicTradesForSitemap(),
  ])

  const profileEntries: MetadataRoute.Sitemap = publicProfiles.map(
    ({ path, lastModified: profileLastModified }) => ({
      url: `${SITE_URL}${path}`,
      lastModified: profileLastModified,
      changeFrequency: "weekly",
      priority: 0.7,
    })
  )

  const tradeEntries: MetadataRoute.Sitemap = publicTrades.map(
    ({ path, lastModified: tradeLastModified }) => ({
      url: `${SITE_URL}${path}`,
      lastModified: tradeLastModified,
      changeFrequency: "weekly",
      priority: 0.6,
    })
  )

  return [...staticEntries, ...profileEntries, ...tradeEntries]
}
