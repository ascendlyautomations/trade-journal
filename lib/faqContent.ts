import {
  TRAXPRO_PLAN_NAME,
  TRAXPRO_TRIAL_LABEL,
} from "@/lib/traxProPricing"
import {
  formatPlanFeaturesList,
  TRADETRAXS_FREE_PLAN,
  TRADETRAXS_PRO_PLAN,
} from "@/lib/tradeTraxsPlans"

/** FAQ copy — shared by the FAQ page and FAQ JSON-LD schema. */
export type FaqItem = {
  question: string
  answer: string
}

export const TRADETRAXS_FAQ_ITEMS: FaqItem[] = [
  {
    question: "What is TradeTraxs?",
    answer:
      "TradeTraxs is a trading journal and social platform where you can track your trades, analyze your performance, and share trades with others.",
  },
  {
    question: "How does TradeTraxs work?",
    answer:
      "TradeTraxs is a cloud-based trading journal and performance analytics platform. You log or import trades, review trading statistics and AI-powered trade analysis, and optionally connect with other traders through Trade Rooms, Direct Messages, and the community feed.",
  },
  {
    question: "How do I get started with TradeTraxs?",
    answer:
      "Create a free account, set up a trading account, and start journaling trades manually or with CSV import on Pro. From there you can explore trading analytics, Clips, Achievements, Trade Rooms, and the rest of the platform at your own pace.",
  },
  {
    question: "Do I need a broker to use TradeTraxs?",
    answer:
      "No. TradeTraxs is trading journal software, not a broker. You can manually add trades or import them from supported brokers. Your broker relationship stays separate from your TradeTraxs journal.",
  },
  {
    question: "Can I manually add trades?",
    answer:
      "Yes. You can manually journal trades with the details that matter to you, including notes and screenshots on Pro. Manual trade tracking is a core part of the TradeTraxs trading journal experience.",
  },
  {
    question: "Can I use TradeTraxs without importing trades?",
    answer:
      "Absolutely. Many traders use TradeTraxs as a manual futures trading journal and never import a file. CSV import is available on Pro when you want faster trade tracking from your broker exports.",
  },
  {
    question: "Can I track multiple trading accounts?",
    answer: `${TRADETRAXS_PRO_PLAN.name} includes unlimited trading accounts. ${TRADETRAXS_FREE_PLAN.name} is designed for getting started with manual trade journaling, Trade Rooms, and social features.`,
  },
  {
    question: "What does the Free plan include?",
    answer: `${TRADETRAXS_FREE_PLAN.description} Includes: ${formatPlanFeaturesList(TRADETRAXS_FREE_PLAN)}.`,
  },
  {
    question: "What does TradeTraxs Pro include?",
    answer: `${TRADETRAXS_PRO_PLAN.description} Includes: ${formatPlanFeaturesList(TRADETRAXS_PRO_PLAN)}.`,
  },
  {
    question: "What stats does TradeTraxs show?",
    answer: `${TRADETRAXS_FREE_PLAN.name} includes basic trading statistics. ${TRAXPRO_PLAN_NAME} unlocks advanced performance analytics, AI Analyst, Backtest Lab, Prop Firm Mode, and advanced trade insights.`,
  },
  {
    question: "Can I share my trades publicly?",
    answer: `Yes. You can post trades to the feed and others can like and comment. Public sharing is included on ${TRADETRAXS_FREE_PLAN.name}.`,
  },
  {
    question: "Can I upload screenshots of my trades?",
    answer: `${TRAXPRO_PLAN_NAME} includes unlimited screenshots. You can attach screenshots when logging trades on Pro.`,
  },
  {
    question: "Can I import trades from a CSV?",
    answer: `CSV import and advanced trade insights are included with ${TRAXPRO_PLAN_NAME}.`,
  },
  {
    question: "Does TradeTraxs support funded accounts?",
    answer: `Yes. ${TRAXPRO_PLAN_NAME} includes Prop Firm Mode to track rule progress on Eval, Funded, and Live accounts.`,
  },
  {
    question: "Can I message other traders?",
    answer: `${TRADETRAXS_FREE_PLAN.name} includes Trade Rooms and social features. ${TRAXPRO_PLAN_NAME} adds unlimited journaling, AI Analyst, Backtest Lab, Prop Firm Mode, and advanced performance analytics.`,
  },
  {
    question: "Is there a leaderboard?",
    answer:
      "Yes, you can see how you rank compared to other traders by P&L and other stats.",
  },
  {
    question: "Do I need to pay to use TradeTraxs?",
    answer: `No. ${TRADETRAXS_FREE_PLAN.name} lets you explore the platform at no cost. ${TRAXPRO_PLAN_NAME} starts at $23.99/month and includes a ${TRAXPRO_TRIAL_LABEL.toLowerCase()}.`,
  },
  {
    question: "Is my data private?",
    answer:
      "Yes, your private trade notes stay private unless you choose to share a trade publicly.",
  },
  {
    question: "What are Clips?",
    answer:
      "Clips are short video moments you can attach to your trading activity so others can see how a setup looked in motion. They help turn a static trade journal into a more visual record of your trading performance.",
  },
  {
    question: "Can I upload videos of my trades?",
    answer:
      "Yes. Clips let you upload short videos related to your trades and share them with the community when you choose. They are a simple way to document entries, exits, and market context beyond screenshots alone.",
  },
  {
    question: "Can I edit or delete a Clip?",
    answer:
      "Yes. You can manage your Clips after uploading them, including removing ones you no longer want on your profile or feed. You stay in control of the video content tied to your TradeTraxs account.",
  },
  {
    question: "Who can see my Clips?",
    answer:
      "Visibility follows how you share them. Public Clips can appear where community content is shown, while private journaling stays private unless you choose to post. You decide what becomes part of your public trading presence.",
  },
  {
    question: "What is AI Analyst?",
    answer: `AI Analyst is TradeTraxs Pro’s AI-powered trade analysis feature. It helps you review your journaled trades and trading performance with clearer context, so you can spot patterns faster than scrolling raw trade history alone.`,
  },
  {
    question: "How does AI Analyst work?",
    answer:
      "AI Analyst looks at the trades and context in your TradeTraxs journal to surface insights about your trading performance. It is designed to support review and reflection, not to place trades or replace your own decision-making.",
  },
  {
    question: "What trading statistics does TradeTraxs calculate?",
    answer:
      "TradeTraxs calculates core trading analytics such as P&L, win rate, and related performance metrics from your journaled trades. Pro unlocks deeper performance analytics and advanced trade insights for more detailed review.",
  },
  {
    question: "Can I track my trading progress over time?",
    answer:
      "Yes. Your trading journal builds a history you can review over time, including performance trends, Achievements, and analytics as you keep logging trades. That makes it easier to see whether your process is improving week to week.",
  },
  {
    question: "Can I compare multiple trading accounts?",
    answer: `Yes on ${TRAXPRO_PLAN_NAME}. You can journal multiple trading accounts and review performance by account, which is especially useful if you run personal, evaluation, and funded accounts side by side.`,
  },
  {
    question: "What is Prop Firm Mode?",
    answer: `Prop Firm Mode is a ${TRAXPRO_PLAN_NAME} feature for prop firm tracking. It helps you monitor rule-oriented progress across evaluation and funded account workflows inside your trading journal.`,
  },
  {
    question: "Can I track evaluation accounts?",
    answer: `Yes. With Prop Firm Mode on ${TRAXPRO_PLAN_NAME}, you can track evaluation accounts alongside your other trading accounts so challenge progress stays organized in one place.`,
  },
  {
    question: "Can I track funded accounts?",
    answer: `Yes. Prop Firm Mode supports funded account tracking so you can journal trades and monitor rule-related progress after you pass an evaluation.`,
  },
  {
    question: "Can I track payouts?",
    answer:
      "Yes. Prop Firm Mode includes payout tracking so you can record and review payouts tied to your funded account workflow. It keeps payout history alongside the rest of your trading journal data.",
  },
  {
    question: "What are Copy Trading Groups?",
    answer: `Copy Trading Groups (Pro) let you journal the same trade across multiple linked accounts in one submission. They are built for traders who run several funded or personal accounts together and want cleaner multi-account trade tracking.`,
  },
  {
    question: "What are Trade Rooms?",
    answer:
      "Trade Rooms are community spaces where traders can discuss markets, share ideas, and stay connected. They are part of the TradeTraxs social experience alongside the feed, follows, and Direct Messages.",
  },
  {
    question: "Can I follow other traders?",
    answer:
      "Yes. You can follow other traders to keep up with shared trades, Clips, and community activity. Following helps you build a feed that reflects the traders you want to learn from.",
  },
  {
    question: "Can I make my profile private?",
    answer:
      "Yes. TradeTraxs supports public and private profile controls so you can limit what others see. Your private trade notes remain private unless you choose to share a trade.",
  },
  {
    question: "Who can see my trading statistics?",
    answer:
      "It depends on your privacy and sharing settings. Private journal details stay with you, while public profile and shared trade content may show selected trading performance information to other users.",
  },
  {
    question: "Which brokers are supported?",
    answer:
      "TradeTraxs supports CSV imports today, and broker integrations are continuously expanding. Traders commonly import from platforms such as Tradovate and NinjaTrader when their export format is supported.",
  },
  {
    question: "Can I import trades from Tradovate?",
    answer: `Yes, when you export a compatible CSV from Tradovate. CSV import is available with ${TRAXPRO_PLAN_NAME}, and broker support continues to expand over time.`,
  },
  {
    question: "Can I import trades from NinjaTrader?",
    answer: `Yes, when you export a compatible CSV from NinjaTrader. Pro CSV import helps you move trade history into your TradeTraxs trading journal without re-entering every fill by hand.`,
  },
  {
    question: "What if my broker isn't supported?",
    answer:
      "You can still use TradeTraxs as a manual trading journal, or import via CSV when your broker provides a compatible export. Broker integrations are continuously expanding, so more direct options may become available over time.",
  },
  {
    question: "Can I upgrade later?",
    answer: `Yes. You can start on ${TRADETRAXS_FREE_PLAN.name} and upgrade to ${TRAXPRO_PLAN_NAME} whenever you want advanced trading analytics, AI Analyst, Prop Firm Mode, CSV import, and other Pro features.`,
  },
  {
    question: "What happens if I downgrade?",
    answer:
      "Your account and historical trades remain available, but Pro-only features become limited or unavailable after the downgrade. You can upgrade again later if you want full Pro access restored.",
  },
  {
    question: "Who owns my trading data?",
    answer:
      "You own your trading data. TradeTraxs stores your journal in the cloud so you can access it across devices, but your trades and notes remain yours. We do not sell your private trading journal data.",
  },
  {
    question: "Can I delete my account?",
    answer:
      "Yes. You can request account deletion from your account settings when you want to leave the platform. Deleting your account removes your TradeTraxs profile and associated personal account data according to our deletion process.",
  },
  {
    question: "Is my payment information secure?",
    answer:
      "Payments are processed by trusted third-party billing providers. TradeTraxs does not store your full card details on our servers. Always use the official TradeTraxs checkout flow when upgrading.",
  },
  {
    question: "Can I use TradeTraxs on my phone?",
    answer:
      "Yes. TradeTraxs is a fully responsive web application, so you can journal trades, check trading analytics, and use community features from a mobile browser on your phone or tablet.",
  },
  {
    question: "Is there a mobile app?",
    answer:
      "TradeTraxs is currently available as a fully responsive web application that works on desktop, tablet, and mobile browsers. Native iOS and Android apps are planned after launch.",
  },
]
