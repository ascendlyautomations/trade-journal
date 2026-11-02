"use client"

import { memo, useEffect, useId, useRef, useState } from "react"
import { ChevronDown } from "lucide-react"

export type FeedMode = "global" | "following"

type FeedModeToggleProps = {
  mode: FeedMode
  onModeChange: (mode: FeedMode) => void
}

const MODE_LABEL: Record<FeedMode, string> = {
  following: "Following",
  global: "Global",
}

function FeedModeToggle({ mode, onModeChange }: FeedModeToggleProps) {
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
    <div className="mb-4 max-md:mb-1">
      <div ref={rootRef} className="relative flex justify-start md:hidden">
        <button
          type="button"
          aria-haspopup="listbox"
          aria-expanded={open}
          aria-controls={menuId}
          aria-label="Feed scope"
          onClick={() => setOpen((v) => !v)}
          className="inline-flex min-h-11 items-center gap-1 rounded-lg px-2 text-[15px] font-semibold tracking-tight text-white"
        >
          <span>{MODE_LABEL[mode]}</span>
          <ChevronDown
            className={`h-3 w-3 text-[color:var(--tt-text-muted,#c0cad6)] ${open ? "rotate-180" : ""}`}
            strokeWidth={2.5}
            aria-hidden
          />
        </button>
        {open ? (
          <ul
            id={menuId}
            role="listbox"
            aria-label="Feed scope"
            className="absolute left-0 top-full z-50 mt-1 min-w-[10rem] overflow-hidden rounded-xl border border-white/15 bg-chrome py-1"
          >
            {(["following", "global"] as const).map((value) => {
              const selected = mode === value
              return (
                <li key={value} role="option" aria-selected={selected}>
                  <button
                    type="button"
                    className={`flex min-h-11 w-full items-center px-3 text-left text-sm font-medium ${
                      selected
                        ? "bg-white/15 text-white"
                        : "text-[color:var(--tt-text-muted,#c0cad6)]"
                    }`}
                    onClick={() => {
                      if (!selected) onModeChange(value)
                      setOpen(false)
                    }}
                  >
                    {MODE_LABEL[value]}
                  </button>
                </li>
              )
            })}
          </ul>
        ) : null}
      </div>

      <div className="hidden justify-center md:flex">
        <div className="flex gap-1 sm:gap-2 bg-white/5 p-1 rounded-xl border border-white/10">
          <button
            type="button"
            onClick={() => onModeChange("following")}
            className={`px-4 py-1.5 rounded-lg text-sm font-medium transition-colors ${
              mode === "following"
                ? "bg-blue-500 text-white shadow-sm"
                : "text-gray-400 hover:text-gray-200"
            }`}
          >
            Following
          </button>

          <button
            type="button"
            onClick={() => onModeChange("global")}
            className={`px-4 py-1.5 rounded-lg text-sm font-medium transition-colors ${
              mode === "global"
                ? "bg-blue-500 text-white shadow-sm"
                : "text-gray-400 hover:text-gray-200"
            }`}
          >
            Global
          </button>
        </div>
      </div>
    </div>
  )
}

export default memo(FeedModeToggle)
