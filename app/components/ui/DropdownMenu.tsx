"use client"

import { useEffect, useRef, useState, type ReactNode } from "react"

export type DropdownMenuItem = {
  id: string
  label: ReactNode
  disabled?: boolean
  onSelect?: () => void
  variant?: "default" | "danger"
}

type DropdownMenuProps = {
  trigger: ReactNode
  items: DropdownMenuItem[]
  align?: "left" | "right"
  disabled?: boolean
  stopPropagation?: boolean
  className?: string
  menuClassName?: string
}

export default function DropdownMenu({
  trigger,
  items,
  align = "right",
  disabled = false,
  stopPropagation = false,
  className = "",
  menuClassName = "",
}: DropdownMenuProps) {
  const [open, setOpen] = useState(false)
  const containerRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return

    function handlePointerDown(event: globalThis.MouseEvent) {
      if (!containerRef.current?.contains(event.target as Node)) {
        setOpen(false)
      }
    }

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") setOpen(false)
    }

    document.addEventListener("mousedown", handlePointerDown)
    document.addEventListener("keydown", handleKeyDown)
    return () => {
      document.removeEventListener("mousedown", handlePointerDown)
      document.removeEventListener("keydown", handleKeyDown)
    }
  }, [open])

  function handleTriggerClick(event: React.MouseEvent<HTMLButtonElement>) {
    if (stopPropagation) event.stopPropagation()
    if (disabled) return
    setOpen((prev) => !prev)
  }

  return (
    <div
      ref={containerRef}
      className={`relative inline-flex ${className}`}
    >
      <button
        type="button"
        onClick={handleTriggerClick}
        disabled={disabled}
        aria-haspopup="menu"
        aria-expanded={open}
        className="inline-flex items-center disabled:opacity-50"
      >
        {trigger}
      </button>

      {open ? (
        <div
          role="menu"
          className={`absolute top-full z-50 mt-1 min-w-[10.5rem] overflow-hidden rounded-lg border border-white/10 bg-[#0f172a] py-1 shadow-xl ${align === "right" ? "right-0" : "left-0"} ${menuClassName}`}
        >
          {items.map((item) => (
            <button
              key={item.id}
              type="button"
              role="menuitem"
              disabled={item.disabled}
              onClick={(event) => {
                event.stopPropagation()
                if (item.disabled || !item.onSelect) return
                item.onSelect()
                setOpen(false)
              }}
              className={`flex w-full items-center px-3 py-2 text-left text-sm transition ${
                item.disabled
                  ? "cursor-default text-gray-400"
                  : item.variant === "danger"
                    ? "text-red-300 hover:bg-white/10"
                    : "text-gray-100 hover:bg-white/10"
              } disabled:opacity-100`}
            >
              {item.label}
            </button>
          ))}
        </div>
      ) : null}
    </div>
  )
}

/** Reserved for future follow-relationship actions (Mute, Block, etc.). */
export const FOLLOW_RELATIONSHIP_FUTURE_MENU_ITEMS: DropdownMenuItem[] = []
