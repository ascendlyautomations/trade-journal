import type { FeedbackPopupInput } from "@/app/components/ui/feedback-popup-types"
import type {
  GettingStartedChecklistItem,
  GettingStartedProgress,
} from "@/lib/gettingStartedChecklist"
import { detectNewlyCompletedTasks } from "@/lib/gettingStartedChecklist"
import { gsDebug } from "@/lib/gettingStartedDebug"
import { feedbackPresets } from "@/lib/feedbackPresets"
import {
  markProgressPopupShownForTasks,
  readShownProgressPopupTaskIds,
} from "@/lib/gettingStartedSticky"

export type ProgressPopupBatch = {
  stepPopups: FeedbackPopupInput[]
  completionPopup: FeedbackPopupInput | null
}

function stepPopupForTask(
  progress: GettingStartedProgress,
  task: GettingStartedChecklistItem
): FeedbackPopupInput {
  return feedbackPresets.gettingStartedProgress(
    progress.completedCount,
    progress.totalCount,
    task.label
  )
}

/**
 * Baseline fetch (first signals load): acknowledge already-complete tasks without popups.
 * Returning users should not see historical task popups on revisit.
 */
export function resolveBaselineProgressPopups(
  progress: GettingStartedProgress,
  userId: string,
  hasSeenOnboardingCompletePopup: boolean
): ProgressPopupBatch {
  const alreadyComplete = progress.items
    .filter((item) => item.complete)
    .map((item) => item.id)

  markProgressPopupShownForTasks(userId, alreadyComplete)

  gsDebug("baseline ack", {
    userId: userId.slice(0, 8),
    alreadyComplete,
    allComplete: progress.allComplete,
  })

  if (progress.allComplete && !hasSeenOnboardingCompletePopup) {
    return {
      stepPopups: [],
      completionPopup: feedbackPresets.onboardingComplete(),
    }
  }

  return { stepPopups: [], completionPopup: null }
}

/**
 * After baseline: compare pre-fetch snapshot to fresh progress; show popup for each
 * newly completed task that has not been acknowledged before.
 */
export function resolveGettingStartedProgressPopups(
  snapshot: GettingStartedProgress,
  progress: GettingStartedProgress,
  userId: string,
  hasSeenOnboardingCompletePopup: boolean
): ProgressPopupBatch {
  const shown = readShownProgressPopupTaskIds(userId)
  const rawNewly = detectNewlyCompletedTasks(snapshot, progress)
  const newlyCompleted = rawNewly.filter((item) => !shown.has(item.id))

  if (rawNewly.length > 0 && newlyCompleted.length === 0) {
    gsDebug("suppressed by shownIds", rawNewly.map((t) => t.id))
  }

  gsDebug("transition resolve", {
    userId: userId.slice(0, 8),
    snapshotCount: snapshot.completedCount,
    progressCount: progress.completedCount,
    newlyCompleted: newlyCompleted.map((t) => t.id),
    shownIds: [...shown],
  })

  for (const item of newlyCompleted) {
    gsDebug("detected task:", item.id)
  }

  if (newlyCompleted.length === 0) {
    return { stepPopups: [], completionPopup: null }
  }

  if (progress.allComplete && !hasSeenOnboardingCompletePopup) {
    markProgressPopupShownForTasks(
      userId,
      newlyCompleted.map((item) => item.id)
    )
    return {
      stepPopups: [],
      completionPopup: feedbackPresets.onboardingComplete(),
    }
  }

  const stepPopups = newlyCompleted.map((task) =>
    stepPopupForTask(progress, task)
  )
  markProgressPopupShownForTasks(
    userId,
    newlyCompleted.map((item) => item.id)
  )

  return { stepPopups, completionPopup: null }
}
