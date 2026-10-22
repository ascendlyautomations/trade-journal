import type { ContextualTourId } from "./types"

/** Mirrors native `tt.contextualTour.dismissed:{userID}` JSON map. */
export function contextualTourStorageKey(userId: string): string {
  return `tt.contextualTour.dismissed:${userId}`
}

export function readDismissedVersions(userId: string): Record<string, number> {
  if (typeof window === "undefined") return {}
  try {
    const raw = localStorage.getItem(contextualTourStorageKey(userId))
    if (!raw) return {}
    const parsed = JSON.parse(raw) as unknown
    if (!parsed || typeof parsed !== "object") return {}
    const out: Record<string, number> = {}
    for (const [key, value] of Object.entries(parsed)) {
      if (typeof value === "number" && Number.isFinite(value)) {
        out[key] = value
      }
    }
    return out
  } catch {
    return {}
  }
}

export function dismissedVersion(
  userId: string,
  tourId: ContextualTourId
): number {
  return readDismissedVersions(userId)[tourId] ?? 0
}

export function dismissTour(
  userId: string,
  tourId: ContextualTourId,
  version: number
): void {
  if (typeof window === "undefined") return
  try {
    const map = readDismissedVersions(userId)
    map[tourId] = Math.max(map[tourId] ?? 0, version)
    localStorage.setItem(
      contextualTourStorageKey(userId),
      JSON.stringify(map)
    )
  } catch {
    // ignore quota / private mode
  }
}
