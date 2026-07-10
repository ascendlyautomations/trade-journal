import type { FeedbackPopupInput } from "@/app/components/ui/feedback-popup-types"
import { feedbackPresets } from "@/lib/feedbackPresets"
import { isFreePlanDailyDmLimitError } from "@/lib/freePlanMessagingLimits"
import { supabaseMutationFeedback } from "@/lib/supabaseMutationFeedback"

/** Standard popup for failed private message sends (includes Free plan DM cap). */
export function dmSendFeedback(
  error: unknown,
  fallbackTitle = "Message Failed"
): FeedbackPopupInput {
  if (isFreePlanDailyDmLimitError(error)) {
    return feedbackPresets.directMessageLimitReached()
  }

  return supabaseMutationFeedback(error, fallbackTitle)
}
