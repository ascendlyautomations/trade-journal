"use client"

import { useCallback, useEffect, useId, useLayoutEffect, useRef, useState } from "react"
import { createPortal } from "react-dom"
import { cn } from "./cn"

export type HelpHintProps = {
  body: string
  className?: string
}

const TOOLTIP_WIDTH_PX = 288
const TOOLTIP_GAP_PX = 8

type TooltipPosition = {
  top: number
  left: number
}

function computeTooltipPosition(
  anchor: DOMRect,
  preferRightAlign: boolean
): TooltipPosition {
  const top = anchor.bottom + TOOLTIP_GAP_PX
  const viewportPadding = 8
  const maxLeft = window.innerWidth - TOOLTIP_WIDTH_PX - viewportPadding

  let left = preferRightAlign
    ? anchor.right - TOOLTIP_WIDTH_PX
    : anchor.left + anchor.width / 2 - TOOLTIP_WIDTH_PX / 2

  left = Math.max(viewportPadding, Math.min(left, maxLeft))

  return { top, left }
}

/** Compact ? help — hover on desktop, tap/click toggle everywhere. */
export default function HelpHint({ body, className }: HelpHintProps) {
  const [open, setOpen] = useState(false)
  const [hoverCapable, setHoverCapable] = useState(false)
  const [position, setPosition] = useState<TooltipPosition | null>(null)
  const rootRef = useRef<HTMLSpanElement>(null)
  const triggerRef = useRef<HTMLButtonElement>(null)
  const tooltipRef = useRef<HTMLSpanElement>(null)
  const tooltipId = useId()

  useEffect(() => {
    const mq = window.matchMedia("(hover: hover) and (pointer: fine)")
    const update = () => setHoverCapable(mq.matches)
    update()
    mq.addEventListener("change", update)
    return () => mq.removeEventListener("change", update)
  }, [])

  const toggleOpen = useCallback(() => {
    setOpen((prev) => !prev)
  }, [])

  useLayoutEffect(() => {
    if (!open) {
      setPosition(null)
      return
    }

    const trigger = triggerRef.current
    if (!trigger) return

    function updatePosition() {
      const anchor = triggerRef.current?.getBoundingClientRect()
      if (!anchor) return
      const alignRight = window.matchMedia("(max-width: 640px)").matches
      setPosition(computeTooltipPosition(anchor, alignRight))
    }

    updatePosition()
    window.addEventListener("resize", updatePosition)
    window.addEventListener("scroll", updatePosition, true)

    return () => {
      window.removeEventListener("resize", updatePosition)
      window.removeEventListener("scroll", updatePosition, true)
    }
  }, [open])

  useEffect(() => {
    if (!open) return

    function handlePointerDown(event: PointerEvent) {
      const target = event.target as Node | null
      if (!target) return
      if (rootRef.current?.contains(target)) return
      if (tooltipRef.current?.contains(target)) return
      setOpen(false)
    }

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") setOpen(false)
    }

    // Bubble phase so the trigger's stopPropagation can keep the tip open.
    document.addEventListener("pointerdown", handlePointerDown)
    document.addEventListener("keydown", handleKeyDown)
    return () => {
      document.removeEventListener("pointerdown", handlePointerDown)
      document.removeEventListener("keydown", handleKeyDown)
    }
  }, [open])

  const bodyParagraphs = body.split("\n\n").filter(Boolean)

  const tooltip =
    open && position ? (
      <span
        ref={tooltipRef}
        id={tooltipId}
        role="tooltip"
        style={{
          top: position.top,
          left: position.left,
          width: TOOLTIP_WIDTH_PX,
        }}
        // Above Getting Started drawers (z-[10000]) and other app chrome.
        className="pointer-events-none fixed z-[11000] rounded-lg border border-white/15 bg-[#0f172a] px-3 py-2.5 text-left shadow-lg"
      >
        <span className="block text-xs font-semibold text-gray-100">How?</span>
        {bodyParagraphs.map((paragraph, index) => (
          <span
            key={index}
            className={cn(
              "block text-xs font-normal leading-relaxed text-gray-300",
              index === 0 ? "mt-1" : "mt-2"
            )}
          >
            {paragraph}
          </span>
        ))}
      </span>
    ) : null

  return (
    <span
      ref={rootRef}
      className={cn("relative inline-flex shrink-0", className)}
      onMouseEnter={() => {
        if (hoverCapable) setOpen(true)
      }}
      onMouseLeave={() => {
        if (hoverCapable) setOpen(false)
      }}
    >
      <button
        ref={triggerRef}
        type="button"
        aria-label="Help"
        aria-expanded={open}
        aria-describedby={open ? tooltipId : undefined}
        onPointerDown={(event) => {
          // Keep parent Link/button from treating this as a row activation.
          event.preventDefault()
          event.stopPropagation()
        }}
        onClick={(event) => {
          event.preventDefault()
          event.stopPropagation()
          // Desktop: click must open (do not toggle-closed after hover already opened).
          // Mobile: tap toggles open/closed.
          if (hoverCapable) setOpen(true)
          else toggleOpen()
        }}
        onKeyDown={(event) => {
          if (event.key === "Enter" || event.key === " ") {
            event.preventDefault()
            event.stopPropagation()
            toggleOpen()
          }
        }}
        className="inline-flex h-5 w-5 cursor-pointer items-center justify-center rounded-full border border-white/20 text-[11px] font-semibold leading-none text-gray-400 transition hover:border-white/35 hover:text-gray-200"
      >
        ?
      </button>
      {typeof document !== "undefined" && tooltip
        ? createPortal(tooltip, document.body)
        : null}
    </span>
  )
}
