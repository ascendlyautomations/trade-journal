"use client"

import { useLayoutEffect, useRef, useState } from "react"
import {
  DASHBOARD_MOBILE_TABS,
  type DashboardMobileTab,
} from "./useDashboardMobileTab"

const TAB_LABELS: Record<DashboardMobileTab, string> = {
  overview: "Overview",
  analytics: "Analytics",
  records: "Records",
}

type DashboardMobileSegmentedControlProps = {
  value: DashboardMobileTab
  onChange: (tab: DashboardMobileTab) => void
}

export default function DashboardMobileSegmentedControl({
  value,
  onChange,
}: DashboardMobileSegmentedControlProps) {
  const trackRef = useRef<HTMLDivElement>(null)
  const buttonRefs = useRef<Partial<Record<DashboardMobileTab, HTMLButtonElement>>>(
    {}
  )
  const [indicator, setIndicator] = useState({ left: 0, width: 0 })

  useLayoutEffect(() => {
    const track = trackRef.current
    const button = buttonRefs.current[value]
    if (!track || !button) return

    const update = () => {
      const trackRect = track.getBoundingClientRect()
      const buttonRect = button.getBoundingClientRect()
      setIndicator({
        left: buttonRect.left - trackRect.left,
        width: buttonRect.width,
      })
    }

    update()
    window.addEventListener("resize", update)
    return () => window.removeEventListener("resize", update)
  }, [value])

  return (
    <div
      ref={trackRef}
      role="tablist"
      aria-label="Dashboard sections"
      className="relative grid w-full grid-cols-3 gap-0.5 rounded-xl border border-white/10 bg-white/10 p-0.5 backdrop-blur-md"
    >
      <div
        aria-hidden
        className="pointer-events-none absolute top-0.5 bottom-0.5 rounded-lg bg-white/15 shadow-sm transition-[left,width] duration-200 ease-out"
        style={{ left: indicator.left, width: indicator.width }}
      />
      {DASHBOARD_MOBILE_TABS.map((tab) => {
        const selected = value === tab
        return (
          <button
            key={tab}
            ref={(node) => {
              if (node) buttonRefs.current[tab] = node
              else delete buttonRefs.current[tab]
            }}
            type="button"
            role="tab"
            aria-selected={selected}
            id={`dashboard-mobile-tab-${tab}`}
            className={`relative z-10 min-h-[36px] rounded-lg px-2 text-[12px] font-semibold tracking-wide transition-colors duration-200 ${
              selected ? "text-white" : "text-gray-300 hover:text-gray-100"
            }`}
            onMouseDown={(event) => {
              // Avoid focus-driven scrollIntoView when switching tabs.
              event.preventDefault()
            }}
            onClick={(event) => {
              onChange(tab)
              event.currentTarget.focus({ preventScroll: true })
            }}
          >
            {TAB_LABELS[tab]}
          </button>
        )
      })}
    </div>
  )
}
