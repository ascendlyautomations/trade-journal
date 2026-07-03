/** Copy for the public /about page — single source for founder-led marketing content. */

export const ABOUT_PAGE_EYEBROW = "About TradeTraxs"

export const ABOUT_HERO = {
  heading: "Built by a Trader, for Traders.",
  subheading:
    "TradeTraxs was created with one simple mission: To give traders a single platform where they can journal, analyze, improve, and connect with others without juggling multiple tools.",
} as const

export const ABOUT_STORY = {
  heading: "Why I Built TradeTraxs",
  paragraphs: [
    "As a trader, I found myself constantly switching between different platforms just to review my performance, journal trades, analyze my edge, and connect with other traders.",
    "Some platforms had great analytics. Others had journaling. Some focused on social features. But nothing brought everything together into one seamless experience.",
    "I wanted a platform where traders could track every trade, understand their strengths and weaknesses, improve through data, and become part of a community that genuinely helps each other grow.",
    "That's why I built TradeTraxs.",
  ],
} as const

export const ABOUT_MISSION = {
  heading: "Our Mission",
  paragraphs: [
    "Our mission is to help traders become more disciplined, data-driven, and consistent by providing the tools they need to understand their performance and continuously improve.",
    "Trading shouldn't rely on guesswork. It should be built on data, reflection, and continuous learning.",
  ],
} as const

export type AboutDifferentiator = {
  icon: string
  title: string
  description: string
}

export const ABOUT_DIFFERENTIATORS: readonly AboutDifferentiator[] = [
  {
    icon: "📈",
    title: "Advanced Performance Analytics",
    description:
      "Discover your strengths with powerful insights and detailed performance tracking.",
  },
  {
    icon: "🤖",
    title: "AI Trade Analyst",
    description:
      "Receive AI-powered feedback designed to help improve your decision making.",
  },
  {
    icon: "🧪",
    title: "Backtest Lab",
    description: "Test ideas and refine strategies before risking real capital.",
  },
  {
    icon: "🏆",
    title: "Prop Firm Mode",
    description:
      "Track evaluations and funded accounts with features built specifically for prop traders.",
  },
  {
    icon: "🎥",
    title: "Trade Replays",
    description: "Review your execution with screenshots and replay videos.",
  },
  {
    icon: "🌍",
    title: "Trading Community",
    description:
      "Share trades, reels, ideas, and learn from traders around the world.",
  },
]

export const ABOUT_LOOKING_AHEAD = {
  heading: "This Is Just the Beginning.",
  paragraphs: [
    "TradeTraxs is constantly evolving. New tools, analytics, and community features are being developed to make the platform even more valuable for traders at every experience level.",
    "This is only the beginning of what TradeTraxs will become.",
  ],
} as const

export const ABOUT_FOUNDER_NOTE = {
  title: "A Note From the Founder",
  paragraphs: [
    "TradeTraxs started as an idea to solve problems I experienced every day as a trader.",
    "Every feature has been built with one goal in mind: helping traders improve.",
    "Whether you're just getting started or managing funded accounts, I hope TradeTraxs becomes a platform that genuinely helps you grow as a trader.",
    "Thank you for being part of the journey.",
  ],
  signature: "Nick Rivard",
  role: "Founder, TradeTraxs",
} as const

export const ABOUT_CTA = {
  heading: "Ready to Start Your Journey?",
  trialLabel: "Start 14-Day Free Trial",
  demoLabel: "Explore Demo",
} as const
