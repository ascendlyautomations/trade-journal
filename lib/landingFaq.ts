import {
  TRAXPRO_PLAN_NAME,
  TRAXPRO_TRIAL_LABEL,
} from "@/lib/traxProPricing"
import {
  formatPlanFeaturesList,
  TRADETRAXS_FREE_PLAN,
  TRADETRAXS_PRO_PLAN,
} from "@/lib/tradeTraxsPlans"

export type LandingFaqItem = { q: string; a: string }

export const LANDING_FAQ_ITEMS: LandingFaqItem[] = [
  {
    q: "What is TradeTraxs?",
    a: "TradeTraxs is the first social platform built specifically for traders — where you can track trades, analyze performance, and connect with a community built for how you actually trade.",
  },
  {
    q: "Can I track multiple trading accounts?",
    a: `${TRADETRAXS_PRO_PLAN.name} includes unlimited trading accounts. ${TRADETRAXS_FREE_PLAN.name} is designed for getting started with manual trade journaling and community features.`,
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
    a: `${TRADETRAXS_FREE_PLAN.name} includes basic trading statistics. ${TRAXPRO_PLAN_NAME} unlocks advanced performance analytics, AI Trade Analyst, Backtest Lab, Prop Firm Mode, and advanced trade insights.`,
  },
  {
    q: "Can I import trades from a CSV?",
    a: `CSV import and advanced trade insights are included with ${TRAXPRO_PLAN_NAME}.`,
  },
  {
    q: "Does TradeTraxs support prop firm accounts?",
    a: `Yes. ${TRAXPRO_PLAN_NAME} includes Prop Firm Mode to track rule progress on Eval, Funded, and Live accounts.`,
  },
  {
    q: "Do I need to pay to use TradeTraxs?",
    a: `No. ${TRADETRAXS_FREE_PLAN.name} lets you explore the platform at no cost. ${TRAXPRO_PLAN_NAME} starts at $23.99/month and includes a ${TRAXPRO_TRIAL_LABEL.toLowerCase()}.`,
  },
  {
    q: "Is my data private?",
    a: "Yes. Your private trade notes stay private unless you choose to share a trade publicly.",
  },
]
