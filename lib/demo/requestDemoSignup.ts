import type { DemoSignupReason } from "./DemoModeContext"
import { isExploreWriteBlocked } from "@/lib/exploreWriteGuard"

let demoSignupHandler: ((reason?: DemoSignupReason) => void) | null = null

export function registerDemoSignupHandler(
  handler: ((reason?: DemoSignupReason) => void) | null
): void {
  demoSignupHandler = handler
}

export function requestDemoSignup(
  reason: DemoSignupReason = "default",
  viewerUserId?: string | null
): void {
  if (!isExploreWriteBlocked(viewerUserId)) return
  demoSignupHandler?.(reason)
}

/** Returns true when the action was blocked and a signup prompt was requested. */
export function blockExploreWrite(
  reason: DemoSignupReason,
  viewerUserId?: string | null
): boolean {
  if (!isExploreWriteBlocked(viewerUserId)) return false
  requestDemoSignup(reason, viewerUserId)
  return true
}
