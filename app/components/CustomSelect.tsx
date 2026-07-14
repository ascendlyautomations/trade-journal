"use client"

import {
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type RefObject,
} from "react"
import { createPortal } from "react-dom"
import {
  ACCOUNT_DROPDOWN_OPTION_CLASS,
  ACCOUNT_DROPDOWN_OPTION_SELECTED_CLASS,
  SELECT_MENU_CLASS,
  SELECT_TRIGGER_CLASS,
} from "@/lib/accountDropdownStyles"

interface Option {
  label: string
  value: string
  disabled?: boolean
}

interface Props {
  value: string
  onChange: (val: string) => void
  options: Option[]
  placeholder?: string
  triggerClassName?: string
  menuClassName?: string
  /** Root wrapper classes (width / shrink). */
  className?: string
  /** Portal target; defaults to document.body. Use modal overlay for correct stacking. */
  portalContainerRef?: RefObject<HTMLElement | null>
  id?: string
  disabled?: boolean
  tabIndex?: number
  "aria-label"?: string
  "aria-labelledby"?: string
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
  triggerClassName = SELECT_TRIGGER_CLASS,
  menuClassName = SELECT_MENU_CLASS,
  className = "",
  portalContainerRef,
  id,
  disabled = false,
  tabIndex = 0,
  "aria-label": ariaLabel,
  "aria-labelledby": ariaLabelledBy,
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
    const viewportPad = 8
    setMenuPosition({
      top: rect.bottom + 4,
      left: Math.min(
        rect.left,
        Math.max(viewportPad, window.innerWidth - rect.width - viewportPad)
      ),
      width: rect.width,
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
  }, [open, disabled])

  useLayoutEffect(() => {
    if (!open) return
    const target = portalContainerRef?.current ?? document.body
    setPortalTarget(target)
  }, [open, portalContainerRef])

  useEffect(() => {
    if (!open) return

    function handleOutsideClick(event: MouseEvent) {
      const target = event.target as Node
      if (rootRef.current?.contains(target)) return
      if (menuRef.current?.contains(target)) return
      setOpen(false)
    }

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") setOpen(false)
    }

    document.addEventListener("mousedown", handleOutsideClick)
    document.addEventListener("keydown", handleKeyDown)
    return () => {
      document.removeEventListener("mousedown", handleOutsideClick)
      document.removeEventListener("keydown", handleKeyDown)
    }
  }, [open])

  useEffect(() => {
    if (disabled) setOpen(false)
  }, [disabled])

  const selected = options.find((opt) => opt.value === value)

  const menu =
    open && menuPosition && !disabled ? (
      <div
        ref={menuRef}
        role="listbox"
        className={menuClassName}
        style={{
          top: menuPosition.top,
          left: menuPosition.left,
          width: menuPosition.width,
        }}
      >
        {options.map((opt) => {
          const isSelected = opt.value === value
          if (opt.disabled) {
            return (
              <div
                key={opt.value}
                className="pointer-events-none select-none px-3 py-1.5 text-xs leading-none text-gray-500"
              >
                {opt.label}
              </div>
            )
          }
          return (
            <button
              key={opt.value}
              type="button"
              role="option"
              aria-selected={isSelected}
              onClick={() => {
                onChange(opt.value)
                setOpen(false)
              }}
              className={`${ACCOUNT_DROPDOWN_OPTION_CLASS} ${
                isSelected ? ACCOUNT_DROPDOWN_OPTION_SELECTED_CLASS : ""
              }`}
            >
              {opt.label}
            </button>
          )
        })}
      </div>
    ) : null

  return (
    <div ref={rootRef} className={`relative w-full min-w-0 ${className}`}>
      <div
        ref={triggerRef}
        id={id}
        role="combobox"
        aria-expanded={open}
        aria-haspopup="listbox"
        aria-label={ariaLabel}
        aria-labelledby={ariaLabelledBy}
        aria-disabled={disabled || undefined}
        tabIndex={disabled ? -1 : tabIndex}
        onClick={() => {
          if (disabled) return
          setOpen((prev) => !prev)
        }}
        onKeyDown={(e) => {
          if (disabled) return
          if (e.key === "Enter" || e.key === " ") {
            e.preventDefault()
            setOpen((prev) => !prev)
          }
        }}
        className={`${triggerClassName} min-w-0 gap-2 ${
          disabled ? "cursor-not-allowed opacity-70" : ""
        }`}
      >
        <span
          className={`min-w-0 flex-1 truncate text-left md:whitespace-normal md:overflow-visible ${
            selected ? "text-white" : "text-gray-400"
          }`}
        >
          {selected?.label ?? placeholder}
        </span>
        <span className="ml-2 shrink-0 text-gray-400" aria-hidden="true">
          ▾
        </span>
      </div>

      {portalTarget && menu ? createPortal(menu, portalTarget) : null}
    </div>
  )
}
