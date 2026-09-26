"use client"

import {
  useCallback,
  useLayoutEffect,
  useRef,
  useState,
  type RefCallback,
} from "react"

/** Left-cluster items: first listed = first moved into More as space shrinks. */
export const DESKTOP_NAV_LEFT_OVERFLOW_ORDER = [
  "community",
  "analytics",
  "messages",
] as const

export type DesktopNavLeftOverflowId =
  (typeof DESKTOP_NAV_LEFT_OVERFLOW_ORDER)[number]

/** Display order inside the More menu (matches full-width navbar order). */
export const DESKTOP_NAV_MORE_DISPLAY_ORDER = [
  "messages",
  "analytics",
  "community",
] as const

export type DesktopNavOverflowId = DesktopNavLeftOverflowId

const GAP_PX = 12 // matches Tailwind gap-3

function sumWithGaps(widths: number[], gap: number): number {
  if (widths.length === 0) return 0
  return widths.reduce((sum, w) => sum + w, 0) + gap * (widths.length - 1)
}

/**
 * Given available width for the nav cluster (pinned + overflowable + More),
 * return which overflowable ids should move into More (prefix of eligibleIds).
 */
export function computeDesktopNavOverflow(args: {
  availableWidth: number
  pinnedWidths: number[]
  itemWidths: Partial<Record<string, number>>
  moreWidth: number
  eligibleIds: readonly string[]
  gap?: number
}): string[] {
  const gap = args.gap ?? GAP_PX
  const { availableWidth, pinnedWidths, itemWidths, moreWidth, eligibleIds } =
    args

  if (availableWidth <= 0) return []

  const pinnedTotal = sumWithGaps(pinnedWidths, gap)
  const afterPinnedGap = pinnedWidths.length > 0 ? gap : 0

  let hiddenCount = 0

  while (hiddenCount <= eligibleIds.length) {
    const visibleIds = eligibleIds.slice(hiddenCount)
    const hiddenIds = eligibleIds.slice(0, hiddenCount)
    const needsMore = hiddenIds.length > 0

    const visibleWidths = visibleIds.map((id) => itemWidths[id] ?? 0)
    const clusterWidths = needsMore
      ? [...visibleWidths, moreWidth]
      : visibleWidths

    const overflowCluster = sumWithGaps(clusterWidths, gap)
    const total =
      pinnedTotal +
      (clusterWidths.length > 0 ? afterPinnedGap + overflowCluster : 0)

    if (total <= availableWidth || hiddenCount === eligibleIds.length) {
      return eligibleIds.slice(0, hiddenCount).map(String)
    }
    hiddenCount += 1
  }

  return eligibleIds.map(String)
}

export function useDesktopNavOverflow(options: {
  enabled: boolean
  /** Changes that affect measured widths (badges, labels). */
  measureKey: string
}) {
  const containerRef = useRef<HTMLDivElement>(null)
  const moreMeasureRef = useRef<HTMLButtonElement>(null)
  const pinnedMeasureRefs = useRef<Map<string, HTMLElement>>(new Map())
  const itemMeasureRefs = useRef<Map<DesktopNavOverflowId, HTMLElement>>(
    new Map()
  )

  const [overflowIds, setOverflowIds] = useState<DesktopNavOverflowId[]>([])
  const overflowIdsRef = useRef(overflowIds)
  overflowIdsRef.current = overflowIds

  const setPinnedRef = useCallback(
    (id: string): RefCallback<HTMLElement> =>
      (el) => {
        if (el) pinnedMeasureRefs.current.set(id, el)
        else pinnedMeasureRefs.current.delete(id)
      },
    []
  )

  const setItemMeasureRef = useCallback(
    (id: DesktopNavOverflowId): RefCallback<HTMLElement> =>
      (el) => {
        if (el) itemMeasureRefs.current.set(id, el)
        else itemMeasureRefs.current.delete(id)
      },
    []
  )

  useLayoutEffect(() => {
    if (!options.enabled) {
      setOverflowIds([])
      return
    }

    const container = containerRef.current
    if (!container) return

    const leftEligible = DESKTOP_NAV_LEFT_OVERFLOW_ORDER

    const measure = () => {
      const rawAvailable = container.clientWidth
      // Avoid writing overflow state while the md:flex cluster is display:none.
      if (rawAvailable <= 0) return

      const pinnedWidths = Array.from(pinnedMeasureRefs.current.values()).map(
        (el) => el.offsetWidth
      )
      const moreWidth = moreMeasureRef.current?.offsetWidth ?? 64

      const itemWidths: Partial<Record<string, number>> = {}
      for (const id of leftEligible) {
        const el = itemMeasureRefs.current.get(id)
        if (el) itemWidths[id] = el.offsetWidth
      }
      const next = computeDesktopNavOverflow({
        availableWidth: rawAvailable,
        pinnedWidths,
        itemWidths,
        moreWidth,
        eligibleIds: leftEligible,
      }) as DesktopNavOverflowId[]

      const prev = overflowIdsRef.current
      const same =
        prev.length === next.length && prev.every((id, i) => id === next[i])
      if (!same) setOverflowIds(next)
    }

    measure()

    const observer = new ResizeObserver(() => {
      measure()
    })
    observer.observe(container)

    const raf = requestAnimationFrame(measure)

    return () => {
      observer.disconnect()
      cancelAnimationFrame(raf)
    }
  }, [options.enabled, options.measureKey])

  const isOverflowing = useCallback(
    (id: DesktopNavOverflowId) => overflowIds.includes(id),
    [overflowIds]
  )

  return {
    containerRef,
    moreMeasureRef,
    setPinnedRef,
    setItemMeasureRef,
    overflowIds,
    isOverflowing,
  }
}
