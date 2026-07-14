import type { MetadataRoute } from "next"
import { SITE_URL } from "@/lib/site"

/** Public marketing and content pages safe for indexing. */
const ALLOW_PATHS = [
  "/",
  "/pricing",
  "/faq",
  "/about",
  "/contact",
  "/affiliate",
  "/explore",
  "/leaderboard",
  "/demo",
  "/help",
  "/legal",
  "/privacy",
  "/terms",
  "/refund-policy",
  "/cookie-policy",
  "/acceptable-use",
  "/copyright",
  "/community-guidelines",
  "/creator-guidelines",
  "/profile/",
  "/trade/",
] as const

/** Private authenticated, admin, and API routes. */
const DISALLOW_PATHS = [
  "/api/",
  "/admin",
  "/dashboard",
  "/trades",
  "/feed",
  "/settings",
  "/messages",
  "/notifications",
  "/community",
  "/analyst",
  "/calendar",
  "/achievements",
  "/import",
  "/backtest",
  "/review",
  "/app",
  "/onboarding",
  "/choose-plan",
  "/reset-password",
  "/finish-trial",
  "/login",
  "/creator",
  "/csv-support",
  "/search",
  "/chat",
  "/streaks",
  "/referrals",
  "/payouts",
  "/beta",
  "/banned",
  "/feedback",
  "/support",
  "/feature-requests",
  "/suggestions",
  "/dev/",
  "/affiliate/dashboard",
  "/affiliate/payout-setup",
  "/analytics/",
] as const

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: "*",
        allow: [...ALLOW_PATHS],
        disallow: [...DISALLOW_PATHS],
      },
    ],
    sitemap: `${SITE_URL}/sitemap.xml`,
    host: SITE_URL,
  }
}
