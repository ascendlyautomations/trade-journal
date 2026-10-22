/** Persists until the user starts or skips the post-onboarding invite (localStorage). */

export function contextualTourAwaitingInviteKey(userId: string): string {
  return `tt.contextualTour.awaitingInvite:${userId}`
}

export function markContextualTourAwaitingInvite(userId: string): void {
  if (typeof window === "undefined") return
  try {
    localStorage.setItem(contextualTourAwaitingInviteKey(userId), "1")
  } catch {
    // ignore quota / private mode
  }
}

export function hasContextualTourAwaitingInvite(userId: string): boolean {
  if (typeof window === "undefined") return false
  try {
    return (
      localStorage.getItem(contextualTourAwaitingInviteKey(userId)) === "1"
    )
  } catch {
    return false
  }
}

export function clearContextualTourAwaitingInvite(userId: string): void {
  if (typeof window === "undefined") return
  try {
    localStorage.removeItem(contextualTourAwaitingInviteKey(userId))
  } catch {
    // ignore
  }
}
