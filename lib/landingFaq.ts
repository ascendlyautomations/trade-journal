import { TRAXPRO_PLAN_NAME } from "@/lib/traxProPricing"
import {
  formatPlanFeaturesList,
  TRADETRAXS_FREE_PLAN,
  TRADETRAXS_PRO_PLAN,
} from "@/lib/tradeTraxsPlans"
import { FREE_PLAN_ACTIVE_TRADING_ACCOUNTS_LABEL } from "@/lib/freePlanDailyLimits"

export type LandingFaqItem = { q: string; a: string }

export const LANDING_FAQ_ITEMS: LandingFaqItem[] = [
  {
    q: "What is TradeTraxs?",
    a: "TradeTraxs is a connected trading platform, not a standalone log. One account on web and iOS combines journaling, performance analytics, psychology check-ins, and a trader-focused social layer (Feed, Trade Rooms, messaging, profiles, achievements, and leaderboards) built around the same trades.",
  },
  {
    q: "How is TradeTraxs different from a traditional trading journal?",
    a: "Most journals stop at recording and reviewing trades. TradeTraxs uses that record across your dashboard, calendar, and profile, and lets you optionally share journaled trades to the Feed, rooms, or DMs, with P&L and context attached, instead of disconnected screenshots in generic social apps.",
  },
  {
    q: "How does psychology tracking work?",
    a: "You can log daily check-ins (such as sleep, mood, focus, and stress) alongside your trading history. TradeTraxs helps you compare mindset entries with performance over time for your own reflection. It does not claim that improving mood or sleep guarantees better trading results.",
  },
  {
    q: "What are Trade Rooms?",
    a: "Trade Rooms are trader communities inside TradeTraxs: group chat organized into sections (like channels), invites, and rich shares such as trades, images, and voice notes. Live voice channels are planned for the future; they are not available today.",
  },
  {
    q: "Can I track multiple trading accounts?",
    a: `${TRADETRAXS_PRO_PLAN.name} includes unlimited trading accounts. ${TRADETRAXS_FREE_PLAN.name} includes ${FREE_PLAN_ACTIVE_TRADING_ACCOUNTS_LABEL.toLowerCase()}, plus journaling, Trade Rooms, messaging, and social features.`,
  },
  {
    q: "What does the Free plan include?",
    a: `${TRADETRAXS_FREE_PLAN.description} Includes: ${formatPlanFeaturesList(TRADETRAXS_FREE_PLAN)}.`,
  },
  {
    q: "What does TradeTraxs Pro include?",
    a: `${TRADETRAXS_PRO_PLAN.description} Includes: ${formatPlanFeaturesList(TRADETRAXS_PRO_PLAN)}.`,
  },
  {
    q: "What stats does TradeTraxs show?",
    a: `${TRADETRAXS_FREE_PLAN.name} includes basic trading statistics. ${TRAXPRO_PLAN_NAME} unlocks advanced performance analytics, AI Analyst, Backtest Lab, Prop Firm Mode, and advanced trade insights.`,
  },
  {
    q: "Can I import trades from a CSV?",
    a: `${TRADETRAXS_FREE_PLAN.name} includes unlimited CSV imports. ${TRAXPRO_PLAN_NAME} adds advanced trade insights, AI Analyst, and other Pro analytics.`,
  },
  {
    q: "Does TradeTraxs sync with brokers?",
    a: `${TRADETRAXS_FREE_PLAN.name} includes broker integrations such as Tradovate and Rithmic where available in Settings, plus unlimited CSV imports. Additional broker platforms may roll out over time.`,
  },
  {
    q: "Is there a native mobile app?",
    a: "TradeTraxs offers a native iOS app on the App Store when the listing URL is configured for your deployment. Android is in development. The full web app works on mobile browsers.",
  },
  {
    q: "Does TradeTraxs support prop firm accounts?",
    a: `Yes. ${TRAXPRO_PLAN_NAME} includes Prop Firm Mode to track rule progress on Eval, Funded, and Live accounts.`,
  },
  {
    q: "Do I need to pay to use TradeTraxs?",
    a: `No. ${TRADETRAXS_FREE_PLAN.name} lets you explore the platform at no cost. ${TRAXPRO_PLAN_NAME} prices, billing periods, and any free trial are shown before Stripe checkout.`,
  },
  {
    q: "Is my data private?",
    a: "Yes. Trades and notes stay private until you choose to share them. Public posts, leaderboard entries, and featured trades only use what you make public.",
  },
]
