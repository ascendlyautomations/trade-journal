/** Primary brand positioning — use consistently across the homepage. */
export const LANDING_BRAND_TAGLINE = "The First Social Platform Built for Traders."

export type LandingFlagship = {
  id: string
  title: string
  tagline: string
  /** Supporting capabilities woven in as bonuses — not headline features. */
  bonuses?: string
  imageSrc: string
  imageAlt: string
  imageObjectPosition?: string
}

export const LANDING_FLAGSHIPS: LandingFlagship[] = [
  {
    id: "flagship-journal",
    title: "Trading Journal",
    tagline:
      "Capture every trade with notes, screenshots, and analytics so every trade becomes a learning opportunity.",
    bonuses: "Calendar · CSV Import · Saved Trades",
    imageSrc: "/images/Trading_Journal.webp",
    imageAlt: "TradeTraxs trading journal with trade entry and notes",
    imageObjectPosition: "object-top",
  },
  {
    id: "flagship-profiles",
    title: "Trader Profiles",
    tagline:
      "Showcase your trading journey, build credibility, and connect with traders who share your goals.",
    bonuses: "Achievements · Followers",
    imageSrc: "/images/Trader_Profiles.webp",
    imageAlt: "Trader profiles on TradeTraxs",
    imageObjectPosition: "object-top",
  },
  {
    id: "flagship-reels",
    title: "Trading Clips",
    tagline:
      "Watch short-form trade breakdowns, educational content, and market insights from traders around the world.",
    imageSrc: "/images/Trading_Reels.webp",
    imageAlt: "Trading clips and short-form content on TradeTraxs",
    imageObjectPosition: "object-top",
  },
  {
    id: "flagship-rooms",
    title: "Trade Rooms",
    tagline:
      "Discuss setups, share charts, and trade alongside other traders in real time. Build yours today!",
    imageSrc: "/images/Trade_Rooms.webp",
    imageAlt: "TradeTraxs trade rooms for real-time trader chat",
    imageObjectPosition: "object-right",
  },
  {
    id: "flagship-propfirm",
    title: "Prop Firm Mode",
    tagline:
      "Track evaluations, monitor firm rules, drawdown, and payout progress so you stay funded with confidence.",
    imageSrc: "/images/Prop_Firm_Mode.webp",
    imageAlt: "TradeTraxs prop firm dashboard and rule tracking",
    imageObjectPosition: "object-center",
  },
  {
    id: "flagship-ai",
    title: "AI Trade Analyst",
    tagline:
      "Discover patterns, uncover mistakes, and receive AI-powered insights that help you become a more consistent trader.",
    bonuses: "Advanced Analytics · Performance Insights",
    imageSrc: "/images/AI_Trade_Analyst.webp",
    imageAlt: "AI trade analysis and review in TradeTraxs",
    imageObjectPosition: "object-center",
  },
]
