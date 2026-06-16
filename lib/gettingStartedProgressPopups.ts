import type { FeedbackPopupInput } from "@/app/components/ui/feedback-popup-types"
import {
  readLastProgressPopupCount,
  readOnboardingCompletePopupShown,
  writeLastProgressPopupCount,
  writeOnboardingCompletePopupShown,
} from "@/lib/gettingStartedSticky"
import type { GettingStartedProgress } from "@/lib/gettingStartedChecklist"
import { feedbackPresets } from "@/lib/feedbackPresets"

export type ProgressPopupBatch = {
  stepPopup: FeedbackPopupInput | null
  completionPopup: FeedbackPopupInput | null
}

/** Seed popup tracking on first dashboard visit; show final popup if already 5/5. */
export function seedGettingStartedProgressPopupsIfNeeded(
  progress: GettingStartedProgress,
  userId: string
): FeedbackPopupInput | null {
  if (readLastProgressPopupCount(userId) !== null) return null

  writeLastProgressPopupCount(userId, progress.completedCount)

  if (progress.allComplete && !readOnboardingCompletePopupShown(userId)) {
    writeOnboardingCompletePopupShown(userId)
    return feedbackPresets.onboardingComplete()
  }

  return null
}

/** Popups when completedCount increases after seeding (incomplete → complete only). */
export function resolveGettingStartedProgressTransition(
  progress: GettingStartedProgress,
  userId: string
): ProgressPopupBatch {
  let lastShown = readLastProgressPopupCount(userId) ?? 0
  const { completedCount, allComplete } = progress

  // Stale storage from prior sessions must not block future step popups.
  if (lastShown > completedCount) {
    lastShown = completedCount
    writeLastProgressPopupCount(userId, lastShown)
  }

  if (completedCount <= lastShown) {
    return { stepPopup: null, completionPopup: null }
  }

  writeLastProgressPopupCount(userId, completedCount)

  if (allComplete) {
    if (readOnboardingCompletePopupShown(userId)) {
      return { stepPopup: null, completionPopup: null }
    }
    writeOnboardingCompletePopupShown(userId)
    return {
      stepPopup: null,
      completionPopup: feedbackPresets.onboardingComplete(),
    }
  }

  return {
    stepPopup: feedbackPresets.gettingStartedProgress(
      completedCount,
      progress.totalCount
    ),
    completionPopup: null,
  }
}
