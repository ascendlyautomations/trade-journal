/**
 * In-app location stack for phone Back. `document.referrer` does not change
 * on Next.js client navigations, so it cannot tell a deep link from a push.
 */
let locations: string[] = []

export function resetMobileWebInAppHistoryForTests(): void {
  locations = []
}

export function syncMobileWebInAppHistory(pathWithSearch: string): void {
  const path = pathWithSearch || "/"
  const previous = locations[locations.length - 2]
  if (previous === path) {
    locations.pop()
    return
  }
  if (locations[locations.length - 1] === path) return
  locations.push(path)
  if (locations.length > 50) locations = locations.slice(-50)
}

export function noteMobileWebHistoryReplace(pathWithSearch: string): void {
  const path = pathWithSearch || "/"
  if (locations.length === 0) locations.push(path)
  else locations[locations.length - 1] = path
}

export function mobileWebBackDecision(): "pop" | "replace" {
  return locations.length > 1 ? "pop" : "replace"
}

export function shouldUseMobileWebHistoryBack(): boolean {
  return mobileWebBackDecision() === "pop"
}

export function followMobileWebBack(
  fallback: string,
  navigate: { back: () => void; replace: (href: string) => void }
): void {
  if (shouldUseMobileWebHistoryBack()) {
    navigate.back()
    return
  }
  noteMobileWebHistoryReplace(fallback)
  navigate.replace(fallback)
}
