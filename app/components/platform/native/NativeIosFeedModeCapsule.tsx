"use client"

import { memo, useEffect, useId, useRef, useState } from "react"
import type { FeedMode } from "@/app/components/feed/FeedModeToggle"
import { hapticLight } from "@/lib/nativeHaptics"

type NativeIosFeedModeCapsuleProps = {
  mode: FeedMode
  onModeChange: (mode: FeedMode) => void
}

const MODE_LABEL: Record<FeedMode, string> = {
  following: "Following",
  global: "Global",
}

/**
 * Compact Following / Global control for the native Feed header.
 * Reads like a small native dropdown; same mode callbacks as FeedModeToggle.
 */
function NativeIosFeedModeCapsule({
  mode,
  onModeChange,
}: NativeIosFeedModeCapsuleProps) {
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
        onClick={() => {
          hapticLight("feed-mode")
          setOpen((v) => !v)
        }}
        className="inline-flex h-8 w-[8.25rem] shrink-0 items-center justify-between gap-1.5 rounded-full border border-white/15 bg-white/10 py-0 pl-3 pr-2.5 text-[12px] font-semibold text-white transition active:bg-white/15"
      >
        <span className="whitespace-nowrap">{MODE_LABEL[mode]}</span>
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
          aria-label="Feed scope"
          className="absolute right-0 top-[calc(100%+6px)] z-50 w-[8.25rem] overflow-hidden rounded-xl border border-white/15 bg-[#0b1f3a] py-1 shadow-lg shadow-black/40"
        >
          {(["following", "global"] as const).map((value) => {
            const selected = mode === value
            return (
              <li key={value} role="option" aria-selected={selected}>
                <button
                  type="button"
                  onClick={() => {
                    if (!selected) {
                      hapticLight("feed-mode")
                      onModeChange(value)
                    }
                    setOpen(false)
                  }}
                  className={`flex w-full items-center px-3 py-2 text-left text-[13px] font-medium transition ${
                    selected
                      ? "bg-white/15 text-white"
                      : "text-white/75 active:bg-white/10 active:text-white"
                  }`}
                >
                  {MODE_LABEL[value]}
                </button>
              </li>
            )
          })}
        </ul>
      ) : null}
    </div>
  )
}

export default memo(NativeIosFeedModeCapsule)
