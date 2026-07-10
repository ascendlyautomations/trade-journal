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
]
