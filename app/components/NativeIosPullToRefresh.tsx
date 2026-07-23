"use client"

import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type MutableRefObject,
  type ReactNode,
  type RefObject,
} from "react"
import { useIsNativeIos } from "@/lib/useIsNativeIos"
import { hapticLight } from "@/lib/nativeHaptics"

const PULL_THRESHOLD_PX = 64
const MAX_PULL_PX = 96

type NativeIosPullToRefreshProps = {
  onRefresh: () => void | Promise<void>
  children: ReactNode
  /**
   * When set, this element is the overflow scroller (messages / trade rooms).
   * The wrapper becomes that scroller; pass the same ref used elsewhere.
   */
  scrollRef?: RefObject<HTMLElement | null>
  /** When true (default if scrollRef set), the root div is the scroll container. */
  useRootAsScroller?: boolean
  className?: string
  disabled?: boolean
}

function getScrollTop(scrollEl: HTMLElement | null): number {
  if (scrollEl) return scrollEl.scrollTop
  return window.scrollY || document.documentElement.scrollTop || 0
}

/**
 * Custom pull-to-refresh for Capacitor iOS only.
 * Works even when html.tt-native sets overscroll-behavior: none,
 * by tracking touch drag from the top of the scroll container.
 * Web / Android: renders children unchanged (no listeners, no spinner).
 */
export default function NativeIosPullToRefresh({
  onRefresh,
  children,
  scrollRef,
  useRootAsScroller = Boolean(scrollRef),
  className,
  disabled = false,
}: NativeIosPullToRefreshProps) {
  const enabled = useIsNativeIos()
  const [pullPx, setPullPx] = useState(0)
  const [refreshing, setRefreshing] = useState(false)
  const [rootNode, setRootNode] = useState<HTMLDivElement | null>(null)
  const pullPxRef = useRef(0)
  const refreshingRef = useRef(false)
  const trackingRef = useRef(false)
  const startYRef = useRef(0)
  const onRefreshRef = useRef(onRefresh)
  onRefreshRef.current = onRefresh

  const setPull = useCallback((px: number) => {
    pullPxRef.current = px
    setPullPx(px)
  }, [])

  const setRootRef = useCallback(
    (node: HTMLDivElement | null) => {
      setRootNode(node)
      if (scrollRef) {
        ;(scrollRef as MutableRefObject<HTMLElement | null>).current = node
      }
    },
    [scrollRef]
  )

  useEffect(() => {
    if (!enabled || disabled) return

    const scrollEl = useRootAsScroller ? rootNode : null
    if (useRootAsScroller && !scrollEl) return

    const target: HTMLElement | Window = scrollEl ?? window

    const onTouchStart = (event: Event) => {
      const touchEvent = event as TouchEvent
      if (refreshingRef.current) return
      if (getScrollTop(scrollEl) > 1) return
      if (touchEvent.touches.length !== 1) return
      trackingRef.current = true
      startYRef.current = touchEvent.touches[0]?.clientY ?? 0
      setPull(0)
    }

    const onTouchMove = (event: Event) => {
      const touchEvent = event as TouchEvent
      if (!trackingRef.current || refreshingRef.current) return
      if (getScrollTop(scrollEl) > 1) {
        trackingRef.current = false
        setPull(0)
        return
      }
      const y = touchEvent.touches[0]?.clientY ?? 0
      const delta = y - startYRef.current
      if (delta <= 0) {
        setPull(0)
        return
      }
      const eased = Math.min(MAX_PULL_PX, delta * 0.45)
      setPull(eased)
      if (eased > 8) {
        touchEvent.preventDefault()
      }
    }

    const finish = async () => {
      if (!trackingRef.current) return
      trackingRef.current = false
      const shouldRefresh =
        pullPxRef.current >= PULL_THRESHOLD_PX && !refreshingRef.current
      if (!shouldRefresh) {
        setPull(0)
        return
      }

      refreshingRef.current = true
      setRefreshing(true)
      setPull(PULL_THRESHOLD_PX * 0.7)
      hapticLight("pull-refresh")
      const scrollBefore = getScrollTop(scrollEl)
      try {
        await onRefreshRef.current()
      } finally {
        if (scrollEl) {
          scrollEl.scrollTop = scrollBefore
        } else {
          window.scrollTo({ top: scrollBefore, left: 0, behavior: "auto" })
        }
        refreshingRef.current = false
        setRefreshing(false)
        setPull(0)
      }
    }

    const onTouchEnd = () => {
      void finish()
    }

    const opts: AddEventListenerOptions = { passive: false }
    target.addEventListener("touchstart", onTouchStart, { passive: true })
    target.addEventListener("touchmove", onTouchMove, opts)
    target.addEventListener("touchend", onTouchEnd, { passive: true })
    target.addEventListener("touchcancel", onTouchEnd, { passive: true })

    return () => {
      target.removeEventListener("touchstart", onTouchStart)
      target.removeEventListener("touchmove", onTouchMove)
      target.removeEventListener("touchend", onTouchEnd)
      target.removeEventListener("touchcancel", onTouchEnd)
    }
  }, [enabled, disabled, rootNode, useRootAsScroller, setPull])

  if (!enabled) {
    return (
      <div ref={setRootRef} className={className}>
        {children}
      </div>
    )
  }

  const progress = Math.min(1, pullPx / PULL_THRESHOLD_PX)
  const showIndicator = pullPx > 4 || refreshing

  return (
    <div ref={setRootRef} className={className}>
      <div
        aria-hidden={!showIndicator}
        className="pointer-events-none sticky top-0 z-[40] flex h-0 justify-center overflow-visible"
      >
        <div
          className="mt-2 flex h-8 w-8 items-center justify-center rounded-full bg-[#0b1f3a]/90 shadow-md shadow-black/30 ring-1 ring-white/10 transition-[opacity,transform] duration-150"
          style={{
            opacity: showIndicator ? 1 : 0,
            transform: `translateY(${Math.max(pullPx - 8, refreshing ? 20 : 0)}px) scale(${0.75 + progress * 0.25})`,
          }}
        >
          <span
            className={`block h-4 w-4 rounded-full border-2 border-white/25 border-t-blue-300 ${
              refreshing || progress >= 1 ? "animate-spin" : ""
            }`}
            style={
              refreshing || progress >= 1
                ? undefined
                : { transform: `rotate(${progress * 360}deg)` }
            }
          />
        </div>
      </div>
      {children}
    </div>
  )
}
