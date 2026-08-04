"use client"

import { memo, useEffect, useId, useRef, useState } from "react"
import { hapticLight } from "@/lib/nativeHaptics"

export type ProfileTradesOutcomeFilter = "all" | "wins" | "losses"

const OUTCOME_LABEL: Record<ProfileTradesOutcomeFilter, string> = {
  all: "All",
  wins: "Wins",
  losses: "Losses",
}

type NativeIosProfileTradesOutcomeFilterProps = {
  value: ProfileTradesOutcomeFilter
  onChange: (value: ProfileTradesOutcomeFilter) => void
}

/**
 * Compact All / Wins / Losses dropdown for native Profile trades.
 * Presentation only — parent filters already-loaded trades.
 */
function NativeIosProfileTradesOutcomeFilter({
  value,
  onChange,
}: NativeIosProfileTradesOutcomeFilterProps) {
  const [open, setOpen] = useState(false)
  const rootRef = useRef<HTMLDivElement | null>(null)
  const menuId = useId()

  useEffect(() => {
    if (!open) return
    function onPointerDown(e: PointerEvent) {
      if (!rootRef.current?.contains(e.target as Node)) setOpen(false)
    }
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false)
    }
    window.addEventListener("pointerdown", onPointerDown)
    window.addEventListener("keydown", onKey)
    return () => {
      window.removeEventListener("pointerdown", onPointerDown)
      window.removeEventListener("keydown", onKey)
    }
  }, [open])

  return (
    <div ref={rootRef} className="relative shrink-0">
      <button
        type="button"
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={menuId}
        aria-label="Filter trades by outcome"
        onClick={() => {
          hapticLight("profile-trades-filter")
          setOpen((v) => !v)
        }}
        className="inline-flex h-8 min-w-[4.75rem] items-center justify-between gap-1.5 rounded-full border border-white/15 bg-white/10 py-0 pl-3 pr-2.5 text-[12px] font-semibold text-white transition active:bg-white/15"
      >
        <span className="whitespace-nowrap">{OUTCOME_LABEL[value]}</span>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="12"
          height="12"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2.5"
          strokeLinecap="round"
          strokeLinejoin="round"
          className={`shrink-0 text-white/70 transition ${open ? "rotate-180" : ""}`}
          aria-hidden
        >
          <polyline points="6 9 12 15 18 9" />
        </svg>
      </button>

      {open ? (
        <ul
          id={menuId}
          role="listbox"
          aria-label="Trade outcome"
          className="absolute left-0 top-[calc(100%+6px)] z-50 min-w-[7.5rem] overflow-hidden rounded-xl border border-white/15 bg-[#0b1f3a] py-1 shadow-lg shadow-black/40"
        >
          {(["all", "wins", "losses"] as const).map((option) => {
            const selected = value === option
            return (
              <li key={option} role="option" aria-selected={selected}>
                <button
                  type="button"
                  onClick={() => {
                    if (!selected) {
                      hapticLight("profile-trades-filter")
                      onChange(option)
                    }
                    setOpen(false)
                  }}
                  className={`flex w-full items-center px-3 py-2 text-left text-[13px] font-medium transition ${
                    selected
                      ? "bg-white/15 text-white"
                      : "text-white/75 active:bg-white/10 active:text-white"
                  }`}
                >
                  {OUTCOME_LABEL[option]}
                </button>
              </li>
            )
          })}
        </ul>
      ) : null}
    </div>
  )
}

export default memo(NativeIosProfileTradesOutcomeFilter)
