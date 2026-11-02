/** html class while the phone Clips pager is full-viewport. */
export const MOBILE_WEB_CLIPS_IMMERSIVE_CLASS =
  "tt-mobile-web-clips-immersive"

const listeners = new Set<() => void>()
let clipsImmersive = false

export function isMobileWebClipsImmersive(): boolean {
  return clipsImmersive
}

export function subscribeMobileWebClipsImmersive(
  listener: () => void
): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

export function setMobileWebClipsImmersive(active: boolean) {
  const next = Boolean(active)
  if (typeof document !== "undefined") {
    document.documentElement.classList.toggle(
      MOBILE_WEB_CLIPS_IMMERSIVE_CLASS,
      next
    )
  }
  if (next === clipsImmersive) return
  clipsImmersive = next
  listeners.forEach((listener) => listener())
}

const CLIPS_POST_KEY = "tt-mobile-web-clips-post"

export function readMobileWebClipsPostId(): string | null {
  if (typeof sessionStorage === "undefined") return null
  try {
    const value = sessionStorage.getItem(CLIPS_POST_KEY)
    return value && value.length > 0 ? value : null
  } catch {
    return null
  }
}

export function writeMobileWebClipsPostId(id: string): void {
  if (typeof sessionStorage === "undefined") return
  try {
    if (!id) sessionStorage.removeItem(CLIPS_POST_KEY)
    else sessionStorage.setItem(CLIPS_POST_KEY, id)
  } catch {
    // Private mode / quota — scroll restore is best-effort.
  }
}

export function formatMobileWebClipCount(value: number): string | null {
  if (!Number.isFinite(value) || value <= 0) return null
  if (value >= 1000) {
    const k = value / 1000
    const text = k >= 10 ? String(Math.round(k)) : k.toFixed(1).replace(/\.0$/, "")
    return `${text}k`
  }
  return String(Math.round(value))
}
