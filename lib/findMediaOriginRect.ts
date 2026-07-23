/**
 * Locate a visible thumbnail that matches a media URL for Photos-style FLIP.
 * Prefers the largest on-screen match so stacked/hidden duplicates are ignored.
 */

function urlsLikelyMatch(candidate: string, target: string): boolean {
  if (!candidate || !target) return false
  if (candidate === target) return true

  try {
    const a = new URL(candidate, window.location.href)
    const b = new URL(target, window.location.href)
    if (a.origin === b.origin && a.pathname === b.pathname) return true

    // Supabase object vs render/image URLs share the same object path suffix.
    const strip = (path: string) =>
      path
        .replace("/storage/v1/render/image/public/", "/storage/v1/object/public/")
        .replace(/\?.*$/, "")
    return strip(a.pathname) === strip(b.pathname)
  } catch {
    return candidate.includes(target) || target.includes(candidate)
  }
}

export function findMediaOriginRect(
  mediaUrl: string | null | undefined
): DOMRect | null {
  if (typeof document === "undefined" || !mediaUrl) return null

  const target = mediaUrl.trim()
  if (!target) return null

  let best: { area: number; rect: DOMRect } | null = null
  const nodes = document.querySelectorAll("img, video")

  for (const node of nodes) {
    let src = ""
    if (node instanceof HTMLImageElement) {
      src = node.currentSrc || node.src
    } else if (node instanceof HTMLVideoElement) {
      src = node.currentSrc || node.src || node.getAttribute("poster") || ""
    }
    if (!urlsLikelyMatch(src, target)) continue

    const rect = node.getBoundingClientRect()
    if (rect.width < 8 || rect.height < 8) continue
    if (rect.bottom < 0 || rect.right < 0) continue
    if (rect.top > window.innerHeight || rect.left > window.innerWidth) continue

    const area = rect.width * rect.height
    if (!best || area > best.area) {
      best = { area, rect: DOMRect.fromRect(rect) }
    }
  }

  return best?.rect ?? null
}
