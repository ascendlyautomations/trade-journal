import { isPhoneWebTouchTarget } from "./mobileWebTouch.ts"

/** Ignore browser-chrome resizes. A real keyboard is taller than this. */
export const MOBILE_WEB_KEYBOARD_OPEN_PX = 120

export type AnchoredMenuPlacement = {
  top: number
  left: number
  width: number
  maxHeight: number
}

/**
 * How much of the layout viewport a phone-web keyboard covers.
 * Smaller changes (Safari toolbar) stay at 0 so the page does not jump.
 */
export function keyboardHeightFromViewport(input: {
  innerHeight: number
  visualHeight: number
  visualOffsetTop: number
  openThreshold?: number
}): number {
  const covered = Math.max(
    0,
    input.innerHeight - input.visualHeight - input.visualOffsetTop
  )
  const threshold = input.openThreshold ?? MOBILE_WEB_KEYBOARD_OPEN_PX
  if (covered < threshold) return 0
  return Math.round(covered)
}

/**
 * Place a portaled menu inside the visible phone-web frame.
 * Coordinates match getBoundingClientRect / position:fixed top.
 * Returns null off phone web so desktop and native keep their own math.
 */
export function anchoredMenuPlacement(input: {
  triggerTop: number
  triggerBottom: number
  triggerLeft: number
  triggerWidth: number
  viewTop: number
  viewBottom: number
  viewLeft: number
  viewRight: number
  preferredMaxHeight: number
  minUsableBelow: number
  minWidth?: number
  gap?: number
  pad?: number
}): AnchoredMenuPlacement {
  const gap = input.gap ?? 4
  const pad = input.pad ?? 8
  const spaceBelow = input.viewBottom - input.triggerBottom - gap - pad
  const spaceAbove = input.triggerTop - input.viewTop - gap - pad
  const openAbove =
    spaceBelow < input.minUsableBelow && spaceAbove > spaceBelow
  const available = Math.max(48, openAbove ? spaceAbove : spaceBelow)
  const maxHeight = Math.min(input.preferredMaxHeight, available)
  const viewWidth = Math.max(0, input.viewRight - input.viewLeft - pad * 2)
  const width = Math.min(
    Math.max(input.triggerWidth, input.minWidth ?? input.triggerWidth),
    viewWidth || input.triggerWidth
  )
  const left = Math.min(
    Math.max(input.viewLeft + pad, input.triggerLeft),
    Math.max(input.viewLeft + pad, input.viewRight - width - pad)
  )
  const top = openAbove
    ? Math.max(input.viewTop + pad, input.triggerTop - gap - maxHeight)
    : input.triggerBottom + gap
  return { top, left, width, maxHeight }
}

export function phoneWebKeyboardCoveredPx(): number {
  if (typeof window === "undefined" || !isPhoneWebTouchTarget()) return 0
  const vv = window.visualViewport
  if (!vv) return 0
  return keyboardHeightFromViewport({
    innerHeight: window.innerHeight,
    visualHeight: vv.height,
    visualOffsetTop: vv.offsetTop,
  })
}

function phoneWebBottomObstructionPx(): number {
  if (phoneWebKeyboardCoveredPx() > 0) return 0
  const raw = getComputedStyle(document.documentElement)
    .getPropertyValue("--app-tab-bar-offset")
    .trim()
  const parsed = Number.parseFloat(raw)
  return Number.isFinite(parsed) ? parsed : 0
}

/** Visible frame in layout-viewport coordinates. Null off phone web. */
export function phoneWebVisibleFrame(): {
  top: number
  right: number
  bottom: number
  left: number
} | null {
  if (typeof window === "undefined" || !isPhoneWebTouchTarget()) return null
  const vv = window.visualViewport
  if (!vv) return null
  return {
    top: vv.offsetTop,
    left: vv.offsetLeft,
    right: vv.offsetLeft + vv.width,
    bottom: vv.offsetTop + vv.height - phoneWebBottomObstructionPx(),
  }
}

export function placePhoneWebAnchoredMenu(input: {
  triggerTop: number
  triggerBottom: number
  triggerLeft: number
  triggerWidth: number
  preferredMaxHeight: number
  minUsableBelow: number
  minWidth?: number
}): AnchoredMenuPlacement | null {
  const frame = phoneWebVisibleFrame()
  if (!frame) return null
  return anchoredMenuPlacement({
    triggerTop: input.triggerTop,
    triggerBottom: input.triggerBottom,
    triggerLeft: input.triggerLeft,
    triggerWidth: input.triggerWidth,
    viewTop: frame.top,
    viewBottom: frame.bottom,
    viewLeft: frame.left,
    viewRight: frame.right,
    preferredMaxHeight: input.preferredMaxHeight,
    minUsableBelow: input.minUsableBelow,
    minWidth: input.minWidth,
  })
}
