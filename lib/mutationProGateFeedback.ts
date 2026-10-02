import type { FeedbackPopupInput } from "@/app/components/ui/feedback-popup-types"
import { supabaseMutationFeedback } from "@/lib/supabaseMutationFeedback"

/**
 * Prefer shared Pro upgrade sheet for limit errors; otherwise return a mutation popup.
 * Returns null when the upgrade sheet handled the error.
 */
export function mutationProGateFeedback(
  fromError: (error: unknown) => boolean,
  error: unknown,
  fallbackTitle: string
): FeedbackPopupInput | null {
  if (fromError(error)) return null
  return supabaseMutationFeedback(error, fallbackTitle)
}
