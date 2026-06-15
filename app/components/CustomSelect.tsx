"use client"

import { useEffect, useLayoutEffect, useRef, useState } from "react"
import { createPortal } from "react-dom"

interface Option {
  label: string
  value: string
}

interface Props {
  value: string
  onChange: (val: string) => void
  options: Option[]
  placeholder?: string
}

type MenuPosition = {
  top: number
  left: number
  width: number
}

export default function CustomSelect({
  value,
  onChange,
  options,
  placeholder = "Select an option",
}: Props) {
  const [open, setOpen] = useState(false)
  const [menuPosition, setMenuPosition] = useState<MenuPosition | null>(null)
  const rootRef = useRef<HTMLDivElement>(null)
  const triggerRef = useRef<HTMLDivElement>(null)
  const menuRef = useRef<HTMLDivElement>(null)

  function updateMenuPosition() {
    const trigger = triggerRef.current
    if (!trigger) return

    const rect = trigger.getBoundingClientRect()
    setMenuPosition({
      top: rect.bottom + 4,
      left: rect.left,
      width: rect.width,
    })
  }

  useLayoutEffect(() => {
    if (!open) {
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
  }, [open])

  useEffect(() => {
    function handleOutsideClick(event: MouseEvent) {
      const target = event.target as Node
      if (rootRef.current?.contains(target)) return
      if (menuRef.current?.contains(target)) return
      setOpen(false)
    }

    document.addEventListener("mousedown", handleOutsideClick)
    return () => document.removeEventListener("mousedown", handleOutsideClick)
  }, [])

  const selected = options.find((opt) => opt.value === value)

  const menu =
    open && menuPosition ? (
      <div
        ref={menuRef}
        className="fixed z-[1100] overflow-hidden rounded-xl border border-white/10 bg-white/10 shadow-lg backdrop-blur-xl"
        style={{
          top: menuPosition.top,
          left: menuPosition.left,
          width: menuPosition.width,
        }}
      >
        {options.map((opt) => {
          const isSelected = opt.value === value
          return (
            <button
              key={opt.value}
              type="button"
              onClick={() => {
                onChange(opt.value)
                setOpen(false)
              }}
              className={`w-full px-4 py-2.5 text-left text-sm text-white focus:outline-none focus:bg-white/20 hover:bg-white/20 ${
                isSelected ? "bg-white/15 font-medium" : ""
              }`}
            >
              {opt.label}
            </button>
          )
        })}
      </div>
    ) : null

  return (
    <div ref={rootRef} className="relative w-full">
      <div
        ref={triggerRef}
        role="button"
        tabIndex={0}
        onClick={() => setOpen((prev) => !prev)}
        onKeyDown={(e) => {
          if (e.key === "Enter" || e.key === " ") {
            e.preventDefault()
            setOpen((prev) => !prev)
          }
        }}
        className="flex w-full cursor-pointer items-center justify-between rounded-xl border border-white/10 bg-white/10 px-4 py-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-400"
      >
        <span className={selected ? "text-white" : "text-gray-400"}>
          {selected?.label ?? placeholder}
        </span>
        <span className="ml-2 shrink-0 text-gray-400">▾</span>
      </div>

      {typeof document !== "undefined" && menu
        ? createPortal(menu, document.body)
        : null}
    </div>
  )
}
