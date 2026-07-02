import {
  TRAXPRO_BILLING_LABEL,
  TRAXPRO_PLAN_NAME,
  TRAXPRO_PRICE_DISPLAY,
  TRAXPRO_TRIAL_LABEL,
} from "@/lib/traxProPricing"
import { FREE_PLAN_ACCOUNT_LIMIT } from "@/lib/tradingAccounts"

export type LandingFaqItem = { q: string; a: string }

export const LANDING_FAQ_ITEMS: LandingFaqItem[] = [
  {
    q: "What is TradeTraxs?",
    a: "TradeTraxs is the first social platform built specifically for traders — where you can track trades, analyze performance, and connect with a community built for how you actually trade.",
  },
  {
    q: "Can I track multiple trading accounts?",
    a: `The Free plan includes up to ${FREE_PLAN_ACCOUNT_LIMIT} trading accounts. ${TRAXPRO_PLAN_NAME} includes unlimited trading accounts.`,
  },
  {
    q: "What does the Free plan include?",
    a: `Free includes: up to ${FREE_PLAN_ACCOUNT_LIMIT} trading accounts; unlimited trade logging; basic dashboard analytics; community access; trade rooms and messaging; public profiles and feed posts; and 1 lifetime CSV import. Upgrade to ${TRAXPRO_PLAN_NAME} for AI Analyst, Backtest Lab, Prop Firm Dashboard, advanced analytics, and unlimited CSV imports.`,
  },
  {
    q: "What stats does TradeTraxs show?",
    a: `You can see P&L, win rate, risk-reward ratio, session performance, equity curve, and more on the Free plan. Advanced dashboard insights require ${TRAXPRO_PLAN_NAME}.`,
  },
  {
    q: "Can I import trades from a CSV?",
    a: `The Free plan includes 1 lifetime CSV import. ${TRAXPRO_PLAN_NAME} includes unlimited CSV imports.`,
  },
  {
    q: "Does TradeTraxs support prop firm accounts?",
    a: `Yes. You can mark accounts as Eval, Funded, or Live. ${TRAXPRO_PLAN_NAME} includes Prop Firm Mode analytics to track rule progress.`,
  },
  {
    q: "Do I need to pay to use TradeTraxs?",
    a: `No. TradeTraxs has a generous Free plan. ${TRAXPRO_PLAN_NAME} is ${TRAXPRO_PRICE_DISPLAY}, ${TRAXPRO_BILLING_LABEL.toLowerCase()}, and includes a ${TRAXPRO_TRIAL_LABEL.toLowerCase()}.`,
  },
  {
    q: "Is my data private?",
    a: "Yes. Your private trade notes stay private unless you choose to share a trade publicly.",
  },
]
