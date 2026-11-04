import { isDemoModeActive } from "@/lib/demo/demoMode"
import { isGuestExploreActive } from "@/lib/guestExplore"
import { isShowcaseUserId } from "@/lib/guestShowcaseAccount"

/**
 * True when the viewer must not mutate data (bundled demo or live showcase guest).
 * DB RLS also enforces guest read-only; this is the product/UI gate + signup prompt.
 */
export function isExploreWriteBlocked(
  viewerUserId?: string | null
): boolean {
  if (isGuestExploreActive()) return true
  if (viewerUserId && isShowcaseUserId(viewerUserId)) return true
  return isDemoModeActive()
}
