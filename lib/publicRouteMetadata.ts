import type { Metadata } from "next"
import { DEFAULT_OG_IMAGE_PATH, SITE_NAME, SITE_URL } from "@/lib/site"
import {
  TRADETRAXS_FREE_PLAN,
  TRADETRAXS_PRO_PLAN,
} from "@/lib/tradeTraxsPlans"

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
  description: `TradeTraxs pricing: ${TRADETRAXS_FREE_PLAN.description} ${TRADETRAXS_PRO_PLAN.name} starts at $23.99/month with a 14-day free trial.`,
})

export const FAQ_PAGE_METADATA = buildPublicRouteMetadata({
  path: "/faq",
  title: "FAQ",
  description:
    "Frequently asked questions about TradeTraxs — trading journal features, accounts, public trades, messaging, and pricing.",
})

export const ABOUT_PAGE_METADATA = buildPublicRouteMetadata({
  path: "/about",
  title: "About TradeTraxs",
  description:
    "Learn why TradeTraxs was created and discover the mission behind the all-in-one trading journal, analytics platform, and trading community.",
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

export const LEGAL_HUB_PAGE_METADATA = buildPublicRouteMetadata({
  path: "/legal",
  title: "Legal",
  description:
    "TradeTraxs legal documents — privacy policy, terms of service, and platform policies.",
})

export const COMMUNITY_GUIDELINES_PAGE_METADATA = buildPublicRouteMetadata({
  path: "/community-guidelines",
  title: "Community Guidelines",
  description:
    "TradeTraxs community guidelines — respectful trading discussions, feedback, and platform conduct.",
})

export const CREATOR_GUIDELINES_PAGE_METADATA = buildPublicRouteMetadata({
  path: "/creator-guidelines",
  title: "Creator Guidelines",
  description:
    "TradeTraxs creator guidelines for sharing trades, posts, and reels with transparency and professionalism.",
})

export const AFFILIATE_PROGRAM_PAGE_METADATA = buildPublicRouteMetadata({
  path: "/affiliate",
  title: "Affiliate Program",
  description:
    "Join the live TradeTraxs Affiliate Program — earn recurring commissions by referring traders to the platform.",
})

export const CONTACT_PAGE_METADATA = buildPublicRouteMetadata({
  path: "/contact",
  title: "Contact",
  description:
    "Contact TradeTraxs for billing, partnerships, business inquiries, and general questions at support@tradetraxs.com.",
})
