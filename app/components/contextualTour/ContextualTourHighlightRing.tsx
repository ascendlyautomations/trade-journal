"use client"

import type { TourRect } from "@/lib/contextualTour/geometry"

type Props = {
  rect: TourRect | null
}

export default function ContextualTourHighlightRing({ rect }: Props) {
  if (!rect) return null

  return (
    <div
      data-tt-contextual-tour-ring
      className="pointer-events-none fixed z-[10074] rounded-lg ring-2 ring-sky-400 ring-offset-2 ring-offset-transparent shadow-[0_0_0_1px_rgba(56,189,248,0.5),0_0_20px_rgba(56,189,248,0.25)] transition-[top,left,width,height] duration-200 ease-out motion-reduce:transition-none"
      style={{
        left: rect.x,
        top: rect.y,
        width: rect.width,
        height: rect.height,
      }}
      aria-hidden
    />
  )
}
