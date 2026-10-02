import type { FeedbackPopupInput } from "@/app/components/ui/feedback-popup-types"
import { feedbackPresets } from "@/lib/feedbackPresets"
import { isFreePlanDailyDmLimitError } from "@/lib/freePlanMessagingLimits"
import { parseProLimitPayload } from "@/lib/proGateReason"
import { supabaseMutationFeedback } from "@/lib/supabaseMutationFeedback"

/** True when the error is a Free-plan DM cap (legacy or PRO_LIMIT_REACHED). */
export function isDmProLimitError(error: unknown): boolean {
  const payload = parseProLimitPayload(error)
  if (payload?.limit === "daily_direct_messages") return true
  return isFreePlanDailyDmLimitError(error)
}

/** Standard popup for failed private message sends (includes Free plan DM cap). */
export function dmSendFeedback(
  error: unknown,
  fallbackTitle = "Message Failed"
): FeedbackPopupInput {
  if (isDmProLimitError(error)) {
    return feedbackPresets.directMessageLimitReached()
  }

  return supabaseMutationFeedback(error, fallbackTitle)
}
