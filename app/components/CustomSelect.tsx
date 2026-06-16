"use client"

import {
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type RefObject,
} from "react"
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
  triggerClassName?: string
  menuClassName?: string
  /** Portal target; defaults to document.body. Use modal overlay for correct stacking. */
  portalContainerRef?: RefObject<HTMLElement | null>
}

const DEFAULT_TRIGGER_CLASS =
  "flex w-full cursor-pointer items-center justify-between rounded-xl border border-white/10 bg-white/10 px-4 py-3 text-sm text-white focus:outline-none focus:ring-2 focus:ring-blue-400"

const DEFAULT_MENU_CLASS =
  "fixed z-[1500] overflow-hidden rounded-xl border border-white/10 bg-[#3d4451] shadow-xl"

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
  triggerClassName = DEFAULT_TRIGGER_CLASS,
  menuClassName = DEFAULT_MENU_CLASS,
  portalContainerRef,
}: Props) {
  const [open, setOpen] = useState(false)
  const [menuPosition, setMenuPosition] = useState<MenuPosition | null>(null)
  const [portalTarget, setPortalTarget] = useState<HTMLElement | null>(null)
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

  useLayoutEffect(() => {
    if (!open) return
    const target = portalContainerRef?.current ?? document.body
    setPortalTarget(target)
  }, [open, portalContainerRef])

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
        className={menuClassName}
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
              className={`w-full px-4 py-2.5 text-left text-sm text-white focus:outline-none focus:bg-white/10 hover:bg-white/10 ${
                isSelected ? "bg-white/10 font-medium" : ""
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
        className={triggerClassName}
      >
        <span className={selected ? "text-white" : "text-gray-400"}>
          {selected?.label ?? placeholder}
        </span>
        <span className="ml-2 shrink-0 text-gray-400">▾</span>
      </div>

      {portalTarget && menu ? createPortal(menu, portalTarget) : null}
    </div>
  )
}
