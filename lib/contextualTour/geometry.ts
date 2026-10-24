import type { ContextualTourTargetId } from "./types"

export const CONTEXTUAL_TOUR_RESOLVE_TIMEOUT_MS = 320

const CHART_LIKE_TARGETS: ReadonlySet<ContextualTourTargetId> = new Set([
  "dashboardPerformance",
])

export function resolveTimeoutMsForTarget(
  targetId: ContextualTourTargetId
): number {
  return CHART_LIKE_TARGETS.has(targetId) ? 1200 : CONTEXTUAL_TOUR_RESOLVE_TIMEOUT_MS
}

export type TourRect = {
  x: number
  y: number
  width: number
  height: number
}

export function isUsableRect(rect: TourRect): boolean {
  return (
    rect.width > 1 &&
    rect.height > 1 &&
    Number.isFinite(rect.x) &&
    Number.isFinite(rect.y) &&
    Number.isFinite(rect.width) &&
    Number.isFinite(rect.height)
  )
}

export function domRectToTourRect(rect: DOMRect): TourRect {
  return {
    x: rect.x,
    y: rect.y,
    width: rect.width,
    height: rect.height,
  }
}

export function intersectionArea(a: TourRect, b: TourRect): number {
  const ix = Math.max(
    0,
    Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x)
  )
  const iy = Math.max(
    0,
    Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y)
  )
  return ix * iy
}

export function isElementTourVisible(el: HTMLElement): boolean {
  if (typeof window === "undefined") return false
  if (!el.isConnected) return false
  const style = window.getComputedStyle(el)
  if (
    style.display === "none" ||
    style.visibility === "hidden" ||
    Number.parseFloat(style.opacity) === 0
  ) {
    return false
  }
  return el.getClientRects().length > 0
}

export function isMeasurableTarget(
  frame: TourRect,
  viewport: TourRect
): boolean {
  if (!isUsableRect(frame) || !isUsableRect(viewport)) return false
  const coversWidth = frame.width >= viewport.width * 0.96
  const coversHeight = frame.height >= viewport.height * 0.72
  return !(coversWidth && coversHeight)
}

export function isRenderableSpotlight(
  frame: TourRect,
  viewport: TourRect
): boolean {
  if (!isUsableRect(frame) || !isUsableRect(viewport)) return false
  if (!isMeasurableTarget(frame, viewport)) return false
  return intersectionArea(frame, viewport) > 64
}

export function skipsTourAutoscroll(target: ContextualTourTargetId): boolean {
  switch (target) {
    case "profileIdentity":
    case "profileTradeRoom":
    case "dashboardTrades":
    case "dashboardNotifications":
    case "dashboardReports":
    case "dashboardWithdrawals":
    case "dashboardCalendar":
    case "feedExplore":
    case "feedTradeRooms":
    case "feedContentFilters":
      return true
    default:
      return false
  }
}

export function needsScroll(
  frame: TourRect,
  viewport: TourRect,
  topInset: number,
  bottomInset: number
): boolean {
  const visible: TourRect = {
    x: viewport.x,
    y: viewport.y + topInset,
    width: viewport.width,
    height: Math.max(0, viewport.height - topInset - bottomInset),
  }
  const ix = Math.max(
    0,
    Math.min(frame.x + frame.width, visible.x + visible.width) -
      Math.max(frame.x, visible.x)
  )
  const iy = Math.max(
    0,
    Math.min(frame.y + frame.height, visible.y + visible.height) -
      Math.max(frame.y, visible.y)
  )
  if (ix <= 0 || iy <= 0) return true
  return iy < frame.height * 0.6 || ix < frame.width * 0.6
}

function scoreTourTargetCandidate(
  el: HTMLElement,
  viewport: TourRect
): number {
  const rect = el.getBoundingClientRect()
  const frame = domRectToTourRect(rect)
  if (!isUsableRect(frame)) return -1
  if (!isRenderableSpotlight(frame, viewport)) return -1

  const visible = intersectionArea(frame, viewport)
  const area = frame.width * frame.height
  const viewportArea = viewport.width * viewport.height
  const allowLarge =
    el.dataset.ttTourSpotlight === "large" ||
    el.getAttribute("data-tt-tour-target") === "dashboardPerformance"
  if (!allowLarge && area > viewportArea * 0.5) return -1

  const visibilityRatio = visible / Math.max(1, area)
  const compactBonus = el.dataset.ttTourPrefer === "compact" ? 2 : 1
  // Prefer smaller, fully visible controls (buttons, nav links) over wide wrappers.
  return (visible * visibilityRatio * compactBonus) / Math.sqrt(area)
}

export function findTourTargetElement(
  targetId: ContextualTourTargetId
): HTMLElement | null {
  if (typeof document === "undefined") return null
  const nodes = document.querySelectorAll(
    `[data-tt-tour-target="${targetId}"]`
  )
  const viewport: TourRect = {
    x: 0,
    y: 0,
    width: window.innerWidth,
    height: window.innerHeight,
  }

  let best: HTMLElement | null = null
  let bestScore = -1

  for (const node of nodes) {
    const el = node as HTMLElement
    if (!isElementTourVisible(el)) continue
    const score = scoreTourTargetCandidate(el, viewport)
    if (score > bestScore) {
      bestScore = score
      best = el
    }
  }

  return best
}
