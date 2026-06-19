import type { FeedbackPopupInput } from "@/app/components/ui/feedback-popup-types"
import { GETTING_STARTED_INTRO_POPUP_TITLE } from "@/lib/gettingStartedIntro"
import { ONBOARDING_COMPLETE_POPUP_TITLE } from "@/lib/gettingStartedOnboardingComplete"
import {
  FREE_PLAN_TRADE_LIMIT_REACHED,
  freePlanCsvImportLimitExceededMessage,
} from "@/lib/freePlanLimits"
import { FREE_PLAN_ACCOUNT_LIMIT_MESSAGE } from "@/lib/tradingAccounts"

export function persistentError(
  title: string,
  message: string
): FeedbackPopupInput {
  return { type: "error", title, message, persist: true }
}

export function persistentWarning(
  title: string,
  message: string
): FeedbackPopupInput {
  return { type: "warning", title, message, persist: true }
}

export function persistentSuccess(
  title: string,
  message: string
): FeedbackPopupInput {
  return { type: "success", title, message, persist: true }
}

export const feedbackPresets = {
  tradeLimitReached: (): FeedbackPopupInput =>
    persistentError(
      FREE_PLAN_TRADE_LIMIT_REACHED.title,
      FREE_PLAN_TRADE_LIMIT_REACHED.description
    ),

  csvImportLimitExceeded: (
    csvTradeCount: number,
    remainingUploads: number
  ): FeedbackPopupInput => {
    const copy = freePlanCsvImportLimitExceededMessage(
      csvTradeCount,
      remainingUploads
    )
    return persistentError(copy.title, copy.description)
  },

  csvSubscriptionLimit: (): FeedbackPopupInput =>
    persistentWarning(
      "CSV Import Unavailable",
      "Free plan includes 1 CSV import. Upgrade to Pro to import more trades."
    ),

  csvImportUnavailable: (): FeedbackPopupInput =>
    persistentWarning(
      "CSV Import Unavailable",
      "Free plan includes one CSV import only. Upgrade to import more."
    ),

  publicTradeLimit: (): FeedbackPopupInput =>
    persistentWarning(
      "Public Trade Limit Reached",
      "Free plan allows 1 public trade per 24 hours. Upgrade to Pro to share more."
    ),

  postLimit: (): FeedbackPopupInput =>
    persistentWarning(
      "Post Limit Reached",
      "Free plan allows 1 post per 24 hours. Upgrade to Pro to post more."
    ),

  messageLimit: (): FeedbackPopupInput =>
    persistentWarning(
      "Message Limit Reached",
      "Free plan allows 10 messages and comments per 24 hours. Upgrade to Pro."
    ),

  accountLimit: (): FeedbackPopupInput =>
    persistentWarning("Account Limit Reached", FREE_PLAN_ACCOUNT_LIMIT_MESSAGE),

  accountLocked: (): FeedbackPopupInput =>
    persistentError(
      "Account Locked",
      "Your free plan is locked to one account. Switch back to that account to save."
    ),

  importFailed: (detail: string): FeedbackPopupInput =>
    persistentError("Import Failed", detail),

  importVerifyFailed: (): FeedbackPopupInput =>
    persistentError(
      "Could Not Verify Limit",
      "Could not verify daily trade limit. Please try again."
    ),

  invalidTradeDate: (): FeedbackPopupInput =>
    persistentError(
      "Invalid Trade Date",
      "Please select a date that is today or earlier."
    ),

  csvImportFutureTradeDate: (): FeedbackPopupInput =>
    persistentError(
      "Invalid Trade Date",
      "One or more trades contain a date in the future. Please correct the dates and try again."
    ),

  invalidStartedTradingDate: (): FeedbackPopupInput =>
    persistentError(
      "Invalid Started Trading Date",
      "Please select a date that is today or earlier."
    ),

  importSuccess: (importedCount: number, skipped = 0): FeedbackPopupInput => {
    let message = `${importedCount} trade${importedCount === 1 ? "" : "s"} imported successfully. They are private by default — edit a trade to make it public.`
    if (skipped > 0) {
      message += ` ${skipped} row(s) were skipped.`
    }
    return persistentSuccess("Import Complete", message)
  },

  tradeSaveSuccess: (): FeedbackPopupInput =>
    persistentSuccess("Trade Saved", "Your trade was saved successfully."),

  profileSaveSuccess: (): FeedbackPopupInput =>
    persistentSuccess("Profile Updated", "Your profile was saved successfully."),

  postPublished: (): FeedbackPopupInput =>
    persistentSuccess(
      "Post Published",
      "Your post is now visible on your profile and in the community feed."
    ),

  gettingStartedIntro: (): FeedbackPopupInput => ({
    type: "info",
    title: GETTING_STARTED_INTRO_POPUP_TITLE,
    message:
      "Your dashboard includes a Getting Started checklist to help you set up TradeTraxs.\n\nComplete tasks like logging trades, following traders, and joining rooms — progress is saved to your account.",
    persist: true,
    dismissLabel: "Got it",
  }),

  gettingStartedProgress: (
    completedCount: number,
    totalCount: number,
    taskLabel: string
  ): FeedbackPopupInput =>
    persistentSuccess(
      "Getting Started Progress",
      `${completedCount}/${totalCount} Complete\n\nCompleted:\n${taskLabel}`
    ),

  onboardingComplete: (): FeedbackPopupInput => ({
    type: "success",
    title: ONBOARDING_COMPLETE_POPUP_TITLE,
    message:
      "Congratulations!\n\nYou have completed all Getting Started tasks and are ready to get the most out of TradeTraxs.",
    persist: true,
    dismissLabel: "Continue Logging",
  }),

  subscriptionCheckoutFailed: (detail: string): FeedbackPopupInput =>
    persistentError("Checkout Failed", detail),
}
