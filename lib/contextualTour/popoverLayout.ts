import type { TourRect } from "./geometry"

export type TourPopoverPlacement = {
  top: number
  left: number
  width: number
}

const CARD_MAX_WIDTH = 360
const CARD_ESTIMATED_HEIGHT = 220
const GAP = 12
const VIEWPORT_MARGIN = 12

export function computeTourPopoverPlacement(
  target: TourRect | null,
  viewport: { width: number; height: number }
): TourPopoverPlacement {
  const width = Math.min(
    CARD_MAX_WIDTH,
    Math.max(280, viewport.width - VIEWPORT_MARGIN * 2)
  )

  if (!target) {
    return {
      width,
      left: Math.max(VIEWPORT_MARGIN, (viewport.width - width) / 2),
      top: Math.max(
        VIEWPORT_MARGIN,
        viewport.height - CARD_ESTIMATED_HEIGHT - VIEWPORT_MARGIN - 16
      ),
    }
  }

  let top = target.y + target.height + GAP
  if (top + CARD_ESTIMATED_HEIGHT > viewport.height - VIEWPORT_MARGIN) {
    top = target.y - CARD_ESTIMATED_HEIGHT - GAP
  }
  if (top < VIEWPORT_MARGIN) {
    top = Math.min(
      viewport.height - CARD_ESTIMATED_HEIGHT - VIEWPORT_MARGIN,
      target.y + target.height + GAP
    )
  }

  let left = target.x + target.width / 2 - width / 2
  left = Math.max(
    VIEWPORT_MARGIN,
    Math.min(left, viewport.width - width - VIEWPORT_MARGIN)
  )

  return { top, left, width }
}

export function computeTourHighlightRect(
  target: TourRect | null,
  pad = 6
): TourRect | null {
  if (!target) return null
  return {
    x: target.x - pad,
    y: target.y - pad,
    width: target.width + pad * 2,
    height: target.height + pad * 2,
  }
}
