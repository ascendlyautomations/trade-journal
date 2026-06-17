import type { MetadataRoute } from "next"
import { SITE_URL } from "@/lib/site"

export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: "*",
      allow: [
        "/",
        "/pricing",
        "/faq",
        "/explore",
        "/leaderboard",
        "/profile/",
        "/trade/",
      ],
      disallow: [
        "/dashboard",
        "/trades",
        "/settings",
        "/admin",
        "/messages",
        "/notifications",
        "/api",
      ],
    },
    sitemap: `${SITE_URL}/sitemap.xml`,
  }
}
