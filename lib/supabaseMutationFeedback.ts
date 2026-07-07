import type { FeedbackPopupInput } from "@/app/components/ui/feedback-popup-types"
import { persistentError } from "@/lib/feedbackPresets"
import {
  logErrorForDevelopers,
  toUserFacingErrorMessage,
} from "@/lib/userFacingError"

/** Map Supabase/Postgres errors to feedback popups with friendly descriptions. */
export function supabaseMutationFeedback(
  error: unknown,
  fallbackTitle: string
): FeedbackPopupInput {
  logErrorForDevelopers(`supabaseMutationFeedback:${fallbackTitle}`, error)
  return persistentError(fallbackTitle, toUserFacingErrorMessage(error))
}

/** Alias for mutation errors outside Supabase (uploads, Stripe, custom throws). */
export const mutationErrorFeedback = supabaseMutationFeedback
