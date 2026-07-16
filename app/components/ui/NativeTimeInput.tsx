"use client"

import {
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type RefObject,
} from "react"
import { createPortal } from "react-dom"
import { cn } from "./cn"
import {
  ACCOUNT_DROPDOWN_OPTION_CLASS,
  ACCOUNT_DROPDOWN_OPTION_SELECTED_CLASS,
  ACCOUNT_DROPDOWN_PORTAL_MENU_CLASS,
} from "@/lib/accountDropdownStyles"
import {
  formatHhmmForDisplay,
  HOUR12_OPTIONS,
  MINUTE_OPTIONS,
  normalizeTradeTimeValue,
  parseTypedTradeTime,
  partsToHhmm,
  PERIOD_OPTIONS,
  type TimeParts,
  type TimePeriod,
  hhmmToParts,
} from "@/lib/tradeTimeInput"

type NativeTimeInputProps = Omit<
  React.InputHTMLAttributes<HTMLInputElement>,
  "type" | "value" | "defaultValue" | "onChange"
> & {
  value?: string
  defaultValue?: string
  onChange?: (event: React.ChangeEvent<HTMLInputElement>) => void
  /** Portal target for the picker menu (e.g. modal overlay). */
  portalContainerRef?: RefObject<HTMLElement | null>
}

type MenuPosition = {
  top?: number
  bottom?: number
  left: number
  width: number
  maxHeight: number
}

const MENU_GAP_PX = 4
const VIEWPORT_PAD_PX = 8
const MENU_PREFERRED_MAX_HEIGHT_PX = 280
const MENU_MIN_USABLE_BELOW_PX = 120

function defaultParts(): TimeParts {
  return { hour12: 9, minute: 30, period: "AM" }
}

/**
 * Cross-browser trade time field (Entry / Exit).
 *
 * Why not native `<input type="time">`?
 * Chromium shows a clock dropdown/spinner on click. Safari on macOS does not
 * provide an equivalent dropdown UI — it exposes editable HH:MM segments (and
 * optional showPicker), which feels like "typing only." That is a platform
 * limitation, not a TradeTraxs bug. Forcing Safari to mimic Chrome's native
 * control is unsupported.
 *
 * Solution: shared text field + portaled hour/minute/AM·PM picker (same portal
 * patterns as CustomSelect). Values stay HH:mm for buildDateTime / DB.
 */
export default function NativeTimeInput({
  className,
  id,
  onFocus,
  onBlur,
  onChange,
  value,
  defaultValue,
  disabled,
  tabIndex,
  portalContainerRef,
  "aria-label": ariaLabel,
  "aria-labelledby": ariaLabelledBy,
  ...props
}: NativeTimeInputProps) {
  const rootRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)
  const menuRef = useRef<HTMLDivElement>(null)
  const hourListRef = useRef<HTMLDivElement>(null)
  const minuteListRef = useRef<HTMLDivElement>(null)

  const controlledHhmm = normalizeTradeTimeValue(value ?? defaultValue ?? "")
  const [draftText, setDraftText] = useState(() =>
    formatHhmmForDisplay(controlledHhmm)
  )
  const [open, setOpen] = useState(false)
  const [menuPosition, setMenuPosition] = useState<MenuPosition | null>(null)
  const [portalTarget, setPortalTarget] = useState<HTMLElement | null>(null)
  const [parts, setParts] = useState<TimeParts>(
    () => hhmmToParts(controlledHhmm) ?? defaultParts()
  )

  // Sync display when parent value changes (e.g. edit trade / CSV fill).
  useEffect(() => {
    if (document.activeElement === inputRef.current) return
    setDraftText(formatHhmmForDisplay(controlledHhmm))
    const nextParts = hhmmToParts(controlledHhmm)
    if (nextParts) setParts(nextParts)
  }, [controlledHhmm])

  function emitHhmm(hhmm: string) {
    if (!onChange) return
    const target = inputRef.current
    onChange({
      target: { value: hhmm } as HTMLInputElement,
      currentTarget: (target ??
        ({ value: hhmm } as HTMLInputElement)) as HTMLInputElement,
    } as React.ChangeEvent<HTMLInputElement>)
  }

  function commitParts(next: TimeParts, close = false) {
    setParts(next)
    const hhmm = partsToHhmm(next.hour12, next.minute, next.period)
    setDraftText(formatHhmmForDisplay(hhmm))
    emitHhmm(hhmm)
    if (close) setOpen(false)
  }

  function commitTypedText(raw: string) {
    const parsed = parseTypedTradeTime(raw)
    if (parsed === null) {
      // Restore last good value
      setDraftText(formatHhmmForDisplay(controlledHhmm))
      return
    }
    if (parsed === "") {
      setDraftText("")
      emitHhmm("")
      return
    }
    const nextParts = hhmmToParts(parsed)
    if (nextParts) setParts(nextParts)
    setDraftText(formatHhmmForDisplay(parsed))
    emitHhmm(parsed)
  }

  function updateMenuPosition() {
    const trigger = rootRef.current
    if (!trigger) return

    const rect = trigger.getBoundingClientRect()
    const spaceBelow =
      window.innerHeight - rect.bottom - MENU_GAP_PX - VIEWPORT_PAD_PX
    const spaceAbove = rect.top - MENU_GAP_PX - VIEWPORT_PAD_PX
    const openAbove =
      spaceBelow < MENU_MIN_USABLE_BELOW_PX && spaceAbove > spaceBelow
    const maxHeight = Math.max(
      160,
      Math.min(
        MENU_PREFERRED_MAX_HEIGHT_PX,
        openAbove ? spaceAbove : spaceBelow
      )
    )
    const width = Math.max(rect.width, 260)
    const left = Math.min(
      rect.left,
      Math.max(VIEWPORT_PAD_PX, window.innerWidth - width - VIEWPORT_PAD_PX)
    )

    if (openAbove) {
      setMenuPosition({
        bottom: window.innerHeight - rect.top + MENU_GAP_PX,
        left,
        width,
        maxHeight,
      })
      return
    }

    setMenuPosition({
      top: rect.bottom + MENU_GAP_PX,
      left,
      width,
      maxHeight,
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
    setPortalTarget(portalContainerRef?.current ?? document.body)
  }, [open, portalContainerRef])

  const draftTextRef = useRef(draftText)
  draftTextRef.current = draftText

  useEffect(() => {
    if (!open) return

    function handleOutsideClick(event: MouseEvent) {
      const target = event.target as Node
      if (rootRef.current?.contains(target)) return
      if (menuRef.current?.contains(target)) return
      setOpen(false)
      commitTypedText(draftTextRef.current)
    }

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key !== "Escape") return
      event.preventDefault()
      event.stopPropagation()
      setOpen(false)
    }

    document.addEventListener("mousedown", handleOutsideClick)
    document.addEventListener("keydown", handleKeyDown, true)
    return () => {
      document.removeEventListener("mousedown", handleOutsideClick)
      document.removeEventListener("keydown", handleKeyDown, true)
    }
  }, [open])

  // Keep selected hour/minute visible when opening.
  useLayoutEffect(() => {
    if (!open) return
    const scrollSelected = (list: HTMLDivElement | null, selected: number) => {
      if (!list) return
      const el = list.querySelector<HTMLElement>(`[data-value="${selected}"]`)
      el?.scrollIntoView({ block: "center" })
    }
    scrollSelected(hourListRef.current, parts.hour12)
    scrollSelected(minuteListRef.current, parts.minute)
  }, [open, parts.hour12, parts.minute])

  function openPicker() {
    if (disabled) return
    const fromValue = hhmmToParts(controlledHhmm) ?? hhmmToParts(
      parseTypedTradeTime(draftText) || ""
    )
    if (fromValue) setParts(fromValue)
    setOpen(true)
  }

  const columnClass =
    "flex-1 overflow-y-auto overscroll-contain py-1 [scrollbar-width:thin]"

  const menu =
    open && menuPosition && !disabled && portalTarget
      ? createPortal(
          <div
            ref={menuRef}
            role="dialog"
            aria-label="Choose time"
            className={cn(ACCOUNT_DROPDOWN_PORTAL_MENU_CLASS, "p-2")}
            style={{
              top: menuPosition.top ?? "auto",
              bottom: menuPosition.bottom ?? "auto",
              left: menuPosition.left,
              width: menuPosition.width,
              maxHeight: menuPosition.maxHeight,
            }}
          >
            <div className="flex gap-1" style={{ maxHeight: menuPosition.maxHeight - 16 }}>
              <div ref={hourListRef} className={columnClass} role="listbox" aria-label="Hour">
                {HOUR12_OPTIONS.map((hour) => {
                  const selected = parts.hour12 === hour
                  return (
                    <button
                      key={hour}
                      type="button"
                      role="option"
                      aria-selected={selected}
                      data-value={hour}
                      className={cn(
                        ACCOUNT_DROPDOWN_OPTION_CLASS,
                        "rounded-md text-center tabular-nums",
                        selected && ACCOUNT_DROPDOWN_OPTION_SELECTED_CLASS
                      )}
                      onClick={() =>
                        commitParts({ ...parts, hour12: hour }, false)
                      }
                    >
                      {hour}
                    </button>
                  )
                })}
              </div>
              <div
                ref={minuteListRef}
                className={columnClass}
                role="listbox"
                aria-label="Minute"
              >
                {MINUTE_OPTIONS.map((minute) => {
                  const selected = parts.minute === minute
                  return (
                    <button
                      key={minute}
                      type="button"
                      role="option"
                      aria-selected={selected}
                      data-value={minute}
                      className={cn(
                        ACCOUNT_DROPDOWN_OPTION_CLASS,
                        "rounded-md text-center tabular-nums",
                        selected && ACCOUNT_DROPDOWN_OPTION_SELECTED_CLASS
                      )}
                      onClick={() =>
                        commitParts({ ...parts, minute }, false)
                      }
                    >
                      {String(minute).padStart(2, "0")}
                    </button>
                  )
                })}
              </div>
              <div className={columnClass} role="listbox" aria-label="AM or PM">
                {PERIOD_OPTIONS.map((period: TimePeriod) => {
                  const selected = parts.period === period
                  return (
                    <button
                      key={period}
                      type="button"
                      role="option"
                      aria-selected={selected}
                      className={cn(
                        ACCOUNT_DROPDOWN_OPTION_CLASS,
                        "rounded-md text-center",
                        selected && ACCOUNT_DROPDOWN_OPTION_SELECTED_CLASS
                      )}
                      onClick={() => commitParts({ ...parts, period }, false)}
                    >
                      {period}
                    </button>
                  )
                })}
              </div>
            </div>
            <div className="mt-2 flex justify-end border-t border-white/10 pt-2">
              <button
                type="button"
                className="rounded-md bg-blue-500 px-3 py-1.5 text-sm font-medium text-white hover:bg-blue-600"
                onClick={() => commitParts(parts, true)}
              >
                Done
              </button>
            </div>
          </div>,
          portalTarget
        )
      : null

  return (
    <div
      ref={rootRef}
      className={cn(
        "tt-time-field relative w-full min-w-0 rounded border border-white/10 bg-[#0f172a]",
        className
      )}
    >
      <input
        {...props}
        ref={inputRef}
        id={id}
        type="text"
        inputMode="text"
        autoComplete="off"
        spellCheck={false}
        disabled={disabled}
        tabIndex={tabIndex}
        aria-label={ariaLabel}
        aria-labelledby={ariaLabelledBy}
        aria-expanded={open}
        aria-haspopup="dialog"
        placeholder="9:30 AM"
        value={draftText}
        onFocus={(e) => {
          onFocus?.(e)
        }}
        onClick={() => {
          openPicker()
        }}
        onChange={(e) => {
          setDraftText(e.target.value)
        }}
        onKeyDown={(e) => {
          if (e.key === "Enter") {
            e.preventDefault()
            commitTypedText(draftText)
            setOpen(false)
            return
          }
          if (e.key === "ArrowDown" && !open) {
            e.preventDefault()
            openPicker()
          }
        }}
        onBlur={(e) => {
          // Delay so picker button/option clicks register first.
          const related = e.relatedTarget as Node | null
          if (menuRef.current?.contains(related)) return
          commitTypedText(draftText)
          onBlur?.(e)
        }}
        className="tt-time-field-input h-full min-h-[2.5rem] w-full cursor-text border-0 bg-transparent p-2 pr-11 text-white outline-none placeholder:text-gray-500"
      />
      <button
        type="button"
        className="tt-time-field-icon"
        aria-label="Open time picker"
        tabIndex={-1}
        disabled={disabled}
        onMouseDown={(e) => {
          e.preventDefault()
        }}
        onClick={() => {
          if (open) {
            setOpen(false)
            commitTypedText(draftText)
          } else {
            openPicker()
            inputRef.current?.focus()
          }
        }}
      >
        <span aria-hidden="true">🕒</span>
      </button>
      {menu}
    </div>
  )
}
