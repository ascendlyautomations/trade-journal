"use client"

import {
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type ReactNode,
} from "react"
import { createPortal } from "react-dom"

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

type MenuPosition = {
  top: number
  left: number
  minWidth: number
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
  const [menuPosition, setMenuPosition] = useState<MenuPosition | null>(null)
  const containerRef = useRef<HTMLDivElement>(null)
  const triggerRef = useRef<HTMLButtonElement>(null)
  const menuRef = useRef<HTMLDivElement>(null)

  function updateMenuPosition() {
    const triggerEl = triggerRef.current
    if (!triggerEl) return
    const rect = triggerEl.getBoundingClientRect()
    const minWidth = Math.max(rect.width, 10.5 * 16)
    const left =
      align === "right"
        ? Math.max(8, rect.right - minWidth)
        : Math.min(rect.left, window.innerWidth - minWidth - 8)
    setMenuPosition({
      top: rect.bottom + 4,
      left,
      minWidth,
    })
  }

  useLayoutEffect(() => {
    if (!open || disabled) {
      setMenuPosition(null)
      return
    }
    updateMenuPosition()
    window.addEventListener("resize", updateMenuPosition)
    window.addEventListener("scroll", updateMenuPosition, true)
    return () => {
      window.removeEventListener("resize", updateMenuPosition)
      window.removeEventListener("scroll", updateMenuPosition, true)
    }
  }, [open, disabled, align])

  useEffect(() => {
    if (!open) return

    function handlePointerDown(event: globalThis.MouseEvent) {
      const target = event.target as Node
      if (containerRef.current?.contains(target)) return
      if (menuRef.current?.contains(target)) return
      setOpen(false)
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

  const menu =
    open && menuPosition ? (
      <div
        ref={menuRef}
        role="menu"
        className={`fixed z-[10070] min-w-[10.5rem] overflow-hidden rounded-lg border border-white/10 bg-[#0f172a] py-1 shadow-xl ${menuClassName}`}
        style={{
          top: menuPosition.top,
          left: menuPosition.left,
          minWidth: menuPosition.minWidth,
        }}
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
    ) : null

  return (
    <div ref={containerRef} className={`relative inline-flex ${className}`}>
      <button
        ref={triggerRef}
        type="button"
        onClick={handleTriggerClick}
        disabled={disabled}
        aria-haspopup="menu"
        aria-expanded={open}
        className="inline-flex items-center disabled:opacity-50"
      >
        {trigger}
      </button>

      {typeof document !== "undefined" && menu
        ? createPortal(menu, document.body)
        : null}
    </div>
  )
}

/** Reserved for future follow-relationship actions (Mute, Block, etc.). */
export const FOLLOW_RELATIONSHIP_FUTURE_MENU_ITEMS: DropdownMenuItem[] = []
