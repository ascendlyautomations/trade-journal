import type { ContextualTourDefinition, ContextualTourStep } from "./types"
import { countsTowardProgress, stepRole } from "./types"

/** Same cutoff as native iOS ContextualTourLaunch. */
export const CONTEXTUAL_TOUR_ACCOUNT_CREATED_AT_CUTOFF_ISO =
  "2026-09-23T00:00:00Z"

const walkthroughSteps: ContextualTourStep[] = [
  {
    target: "dashboardAccountAndDates",
    title: "Accounts & timeframe",
    message: "Pick which account and period the Dashboard uses.",
    surface: "dashboard",
  },
  {
    target: "dashboardPerformance",
    title: "Equity curve",
    message: "See how your account has performed over time.",
    surface: "dashboard",
    presentsIfUnmeasured: true,
  },
  {
    target: "dashboardTrades",
    title: "Trades",
    message: "Review your full trade journal.",
    surface: "dashboard",
  },
  {
    target: "dashboardReports",
    title: "Reports",
    message: "Weekly and monthly performance breakdowns.",
    surface: "dashboard",
    presentsIfUnmeasured: true,
  },
  {
    target: "dashboardWithdrawals",
    title: "Withdrawals",
    message: "Track live and prop-firm payouts.",
    surface: "dashboard",
  },
  {
    target: "dashboardCalendar",
    title: "Calendar",
    message: "Review performance day by day.",
    surface: "dashboard",
    presentsIfUnmeasured: true,
  },
  {
    target: "dashboardNotifications",
    title: "Notifications",
    message: "Social updates and activity alerts.",
    surface: "dashboard",
    presentsIfUnmeasured: true,
  },
  {
    title: "Continue to Feed",
    message: "",
    surface: "dashboard",
    role: "sectionContinue",
  },
  {
    target: "feedContentFilters",
    title: "Feed filters",
    message: "Filter by trades, posts, clips, and more.",
    surface: "feed",
    presentsIfUnmeasured: true,
  },
  {
    target: "feedTradeRooms",
    title: "Trade Rooms",
    message: "Chat and trade with your communities.",
    surface: "feed",
    presentsIfUnmeasured: true,
  },
  {
    target: "feedExplore",
    title: "Explore",
    message: "Find traders and content across TradeTraxs.",
    surface: "feed",
    presentsIfUnmeasured: true,
  },
  {
    title: "Continue to Profile",
    message: "",
    surface: "feed",
    role: "sectionContinue",
  },
  {
    target: "profileIdentity",
    title: "Profile",
    message: "Your identity, social info, and trading stats.",
    surface: "profile",
    presentsIfUnmeasured: true,
  },
  {
    target: "profileTradeRoom",
    title: "Your Trade Room",
    message: "Your community space for market discussion.",
    surface: "profile",
    presentsIfUnmeasured: true,
  },
  {
    target: "settingsBroker",
    title: "Broker connections",
    message: "Link Tradovate or Rithmic to import trades automatically.",
    surface: "settings",
    presentsIfUnmeasured: true,
  },
  {
    target: "settingsAppearance",
    title: "Appearance",
    message: "Choose System, Light, or Dark mode.",
    surface: "settings",
    presentsIfUnmeasured: true,
  },
  {
    title: "You're all set",
    message: "Replay this walkthrough anytime in Settings.",
    surface: "settings",
    role: "finish",
  },
]

export const CONTEXTUAL_TOUR_DASHBOARD: ContextualTourDefinition = {
  id: "dashboard",
  version: 1,
  steps: walkthroughSteps,
}

export function informationalStepCount(definition: ContextualTourDefinition): number {
  return definition.steps.filter((step) =>
    countsTowardProgress(stepRole(step))
  ).length
}
