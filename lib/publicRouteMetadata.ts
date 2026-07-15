import { buildSeoMetadata } from "@/lib/seoMetadata"
import { SUPPORT_EMAIL } from "@/lib/contactEmails"
import {
  TRADETRAXS_FREE_PLAN,
  TRADETRAXS_PRO_PLAN,
} from "@/lib/tradeTraxsPlans"
import { SITE_KEYWORDS } from "@/lib/site"

function publicPage(
  path: `/${string}`,
  title: string,
  description: string
) {
  return buildSeoMetadata({ path, title, description })
}

export const EXPLORE_PAGE_METADATA = publicPage(
  "/explore",
  "Explore Traders",
  "Discover active traders on TradeTraxs. Search profiles, find top performers, and follow traders in the social trading community."
)

export const LEADERBOARD_PAGE_METADATA = publicPage(
  "/leaderboard",
  "Trading Leaderboard",
  "Compare trading performance on the TradeTraxs leaderboard. View P&L rankings, win rate, and community stats from our social trading platform."
)

export const PRICING_PAGE_METADATA = buildSeoMetadata({
  path: "/pricing",
  title: "Pricing",
  description: `TradeTraxs pricing for the social trading platform. ${TRADETRAXS_FREE_PLAN.description} ${TRADETRAXS_PRO_PLAN.name} from $23.99/month with a 14-day free trial.`,
})

export const FAQ_PAGE_METADATA = publicPage(
  "/faq",
  "FAQ",
  "Frequently asked questions about TradeTraxs, the social trading platform with an AI trading journal, Trade Rooms, messaging, and pricing."
)

export const ABOUT_PAGE_METADATA = publicPage(
  "/about",
  "About TradeTraxs",
  "Learn about TradeTraxs, the social trading platform with an AI trading journal and advanced analytics for active and futures traders."
)

export const HELP_PAGE_METADATA = publicPage(
  "/help",
  "Help Center",
  "Get help with TradeTraxs, the social trading platform for journaling trades, sharing clips, and analyzing performance. Contact support or browse the FAQ."
)

export const PRIVACY_PAGE_METADATA = publicPage(
  "/privacy",
  "Privacy Policy",
  "TradeTraxs Privacy Policy, how we collect, use, and protect account, trading journal, and community data."
)

export const TERMS_PAGE_METADATA = publicPage(
  "/terms",
  "Terms of Service",
  "TradeTraxs Terms of Service, account rules, subscriptions, user content, and platform disclaimers."
)

export const REFUND_POLICY_PAGE_METADATA = publicPage(
  "/refund-policy",
  "Refund Policy",
  "TradeTraxs Refund Policy, subscription billing, cancellation, and non-refundable purchase terms."
)

export const COOKIE_POLICY_PAGE_METADATA = publicPage(
  "/cookie-policy",
  "Cookie Policy",
  "TradeTraxs Cookie Policy, how we use cookies for authentication, billing, and preferences on the social trading platform."
)

export const ACCEPTABLE_USE_PAGE_METADATA = publicPage(
  "/acceptable-use",
  "Acceptable Use Policy",
  "TradeTraxs Acceptable Use Policy, standards for lawful, respectful, and safe use of the social trading platform."
)

export const COPYRIGHT_PAGE_METADATA = publicPage(
  "/copyright",
  "Copyright & DMCA Policy",
  "TradeTraxs Copyright & DMCA Policy, report infringing content and understand our repeat infringer policy."
)

export const LEGAL_HUB_PAGE_METADATA = publicPage(
  "/legal",
  "Legal",
  "TradeTraxs legal documents, privacy policy, terms of service, refund policy, and platform policies."
)

export const COMMUNITY_GUIDELINES_PAGE_METADATA = publicPage(
  "/community-guidelines",
  "Community Guidelines",
  "TradeTraxs community guidelines for respectful trading discussions, feedback, and platform conduct."
)

export const CREATOR_GUIDELINES_PAGE_METADATA = publicPage(
  "/creator-guidelines",
  "Creator Guidelines",
  "TradeTraxs creator guidelines for sharing trades, posts, and clips with transparency on the social trading platform."
)

export const AFFILIATE_PROGRAM_PAGE_METADATA = publicPage(
  "/affiliate",
  "Affiliate Program",
  "Join the TradeTraxs Affiliate Program, earn recurring commissions by referring traders to our social trading platform."
)

export const CONTACT_PAGE_METADATA = publicPage(
  "/contact",
  "Contact",
  `Contact TradeTraxs for billing, partnerships, and questions about our social trading platform at ${SUPPORT_EMAIL}.`
)

export const LOGIN_PAGE_METADATA = buildSeoMetadata({
  path: "/login",
  title: "Sign In",
  description:
    "Sign in to TradeTraxs, the social trading platform for journaling trades, analyzing performance with AI, and connecting with traders.",
  index: false,
})

export const DEMO_PAGE_METADATA = buildSeoMetadata({
  path: "/demo",
  title: "Interactive Demo",
  description:
    "Try the TradeTraxs interactive demo. Explore the social trading platform, AI journal, analytics, and community features before you sign up.",
  index: true,
})

export const CSV_SUPPORT_PAGE_METADATA = buildSeoMetadata({
  path: "/csv-support",
  title: "CSV Import Support",
  description:
    "Get help importing broker CSV files into TradeTraxs, the social trading platform with CSV import on Pro.",
  index: false,
})

/** Keywords for indexable marketing pages. */
export const MARKETING_KEYWORDS = [...SITE_KEYWORDS]
