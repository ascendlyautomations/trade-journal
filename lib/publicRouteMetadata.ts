import type { Metadata } from "next"
import { DEFAULT_OG_IMAGE_PATH, SITE_NAME, SITE_URL } from "@/lib/site"

type PublicRouteMetaInput = {
  path: `/${string}`
  title: string
  description: string
}

function buildPublicRouteMetadata({
  path,
  title,
  description,
}: PublicRouteMetaInput): Metadata {
  const absoluteTitle = `${title} | ${SITE_NAME}`
  const url = `${SITE_URL}${path}`

  return {
    title: { absolute: absoluteTitle },
    description,
    alternates: {
      canonical: path,
    },
    openGraph: {
      type: "website",
      url,
      title: absoluteTitle,
      description,
      siteName: SITE_NAME,
      images: [
        {
          url: DEFAULT_OG_IMAGE_PATH,
          alt: SITE_NAME,
        },
      ],
    },
    twitter: {
      card: "summary_large_image",
      title: absoluteTitle,
      description,
      images: [DEFAULT_OG_IMAGE_PATH],
    },
  }
}

export const EXPLORE_PAGE_METADATA = buildPublicRouteMetadata({
  path: "/explore",
  title: "Explore Traders",
  description:
    "Discover active traders, top performers, and new members on TradeTraxs. Search profiles and find traders to follow.",
})

export const LEADERBOARD_PAGE_METADATA = buildPublicRouteMetadata({
  path: "/leaderboard",
  title: "Trading Leaderboard",
  description:
    "Compare trading performance on the TradeTraxs leaderboard. View rankings, P&L, win rate, and community stats.",
})

export const PRICING_PAGE_METADATA = buildPublicRouteMetadata({
  path: "/pricing",
  title: "Pricing",
  description:
    "TradeTraxs pricing: start free with 3 accounts and unlimited trades, or upgrade to TraxPro ($23.99 every 4 weeks) for AI insights, advanced analytics, and unlimited accounts.",
})

export const FAQ_PAGE_METADATA = buildPublicRouteMetadata({
  path: "/faq",
  title: "FAQ",
  description:
    "Frequently asked questions about TradeTraxs — trading journal features, accounts, public trades, messaging, and pricing.",
})

export const HELP_PAGE_METADATA = buildPublicRouteMetadata({
  path: "/help",
  title: "Help Center",
  description:
    "Get help with TradeTraxs. Contact support, submit feedback, report bugs, or find answers in the FAQ.",
})

export const PRIVACY_PAGE_METADATA = buildPublicRouteMetadata({
  path: "/privacy",
  title: "Privacy Policy",
  description:
    "TradeTraxs Privacy Policy — how we collect, use, and protect account, trading, and community data.",
})

export const TERMS_PAGE_METADATA = buildPublicRouteMetadata({
  path: "/terms",
  title: "Terms of Service",
  description:
    "TradeTraxs Terms of Service — account rules, subscriptions, user content, and platform disclaimers.",
})
