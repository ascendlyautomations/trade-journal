import type { ContextualTourTargetId } from "./types"

export const CONTEXTUAL_TOUR_RESOLVE_TIMEOUT_MS = 1200
export const CONTEXTUAL_TOUR_STABILITY_TOLERANCE_PX = 1

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

export function isStableRect(previous: TourRect, current: TourRect): boolean {
  const t = CONTEXTUAL_TOUR_STABILITY_TOLERANCE_PX
  return (
    Math.abs(previous.x - current.x) <= t &&
    Math.abs(previous.y - current.y) <= t &&
    Math.abs(previous.width - current.width) <= t &&
    Math.abs(previous.height - current.height) <= t
  )
}

export function isMeasurableTarget(
  frame: TourRect,
  viewport: TourRect
): boolean {
  if (!isUsableRect(frame) || !isUsableRect(viewport)) return false
  const coversScreen =
    frame.width >= viewport.width * 0.98 &&
    frame.height >= viewport.height * 0.85
  return !coversScreen
}

export function isRenderableSpotlight(
  frame: TourRect,
  viewport: TourRect
): boolean {
  if (!isMeasurableTarget(frame, viewport)) return false
  const nearby = {
    x: viewport.x - 32,
    y: viewport.y - 32,
    width: viewport.width + 64,
    height: viewport.height + 64,
  }
  return rectsIntersect(frame, nearby)
}

function rectsIntersect(a: TourRect, b: TourRect): boolean {
  return (
    a.x < b.x + b.width &&
    a.x + a.width > b.x &&
    a.y < b.y + b.height &&
    a.y + a.height > b.y
  )
}

export function skipsTourAutoscroll(target: ContextualTourTargetId): boolean {
  return target === "profileIdentity" || target === "profileTradeRoom"
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

export function findTourTargetElement(
  targetId: ContextualTourTargetId
): HTMLElement | null {
  if (typeof document === "undefined") return null
  const nodes = document.querySelectorAll(
    `[data-tt-tour-target="${targetId}"]`
  )
  for (const node of nodes) {
    const el = node as HTMLElement
    const rect = el.getBoundingClientRect()
    if (rect.width > 1 && rect.height > 1) return el
  }
  return (nodes[0] as HTMLElement | null) ?? null
}
