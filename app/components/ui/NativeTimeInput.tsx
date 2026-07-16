"use client"

import { useLayoutEffect, useRef, useState } from "react"
import { cn } from "./cn"
import {
  openNativeTimePicker,
  useDismissNativeTemporalField,
} from "./NativeDateInput"

type NativeTimeInputProps = Omit<
  React.InputHTMLAttributes<HTMLInputElement>,
  "type"
>

/**
 * Normalize to HH:MM for trade forms (Safari may emit HH:MM:SS).
 */
function normalizeTimeValue(raw: string): string {
  const s = String(raw ?? "").trim()
  if (!s) return ""
  const match = /^(\d{1,2}):(\d{2})/.exec(s)
  if (!match) return s
  return `${String(Number(match[1])).padStart(2, "0")}:${match[2]}`
}

/**
 * Cross-browser time field for trade forms.
 *
 * Root cause (Safari / WebKit only):
 * A React-controlled `<input type="time" value={...}>` writes the DOM
 * `.value` on every re-render. WebKit’s time control edits HH / MM as
 * separate shadow-DOM segments; assigning `.value` mid-edit resets the
 * caret, overwrites the in-progress segment, or drops the keystroke.
 * Chromium tolerates the same controlled pattern, which is why Windows/
 * Chrome appeared fine while macOS/iOS Safari did not.
 *
 * Fix (shared, not Apple-only): keep the input uncontrolled for React
 * (`value` prop never set). Sync from props imperatively only while
 * blurred. Still forward onChange so parent state / duration stay live.
 *
 * Clock affordance: an explicit button calls showPicker() (Safari macOS +
 * Chromium) or focus/click (iOS wheel). Do not stretch the native
 * calendar-picker-indicator over the full field — that blocks segment edits.
 */
export default function NativeTimeInput({
  className,
  id,
  onFocus,
  onClick,
  onChange,
  onBlur,
  onInput,
  value,
  defaultValue,
  step = 60,
  ...props
}: NativeTimeInputProps) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [focused, setFocused] = useState(false)
  useDismissNativeTemporalField(inputRef)

  const normalizedValue = normalizeTimeValue(
    String(value ?? defaultValue ?? "")
  )

  // Sync external value → DOM only when not editing. Writing `.value`
  // while focused is exactly what breaks Safari segment typing.
  useLayoutEffect(() => {
    if (focused) return
    const input = inputRef.current
    if (!input) return
    if (input.value !== normalizedValue) {
      input.value = normalizedValue
    }
  }, [normalizedValue, focused])

  const openClock = (e: React.SyntheticEvent) => {
    e.preventDefault()
    e.stopPropagation()
    openNativeTimePicker(inputRef.current)
  }

  return (
    <div
      className={cn(
        "tt-time-field w-full min-w-0 cursor-pointer rounded border border-white/10 bg-[#0f172a]",
        className
      )}
    >
      <input
        {...props}
        ref={inputRef}
        id={id}
        type="time"
        step={step}
        // Uncontrolled: do not pass `value`. defaultValue stays "" so iOS
        // Clear empties the field; displayed value is set via layout effect.
        defaultValue=""
        onFocus={(e) => {
          setFocused(true)
          onFocus?.(e)
        }}
        onClick={(e) => {
          onClick?.(e)
        }}
        onInput={(e) => {
          onInput?.(e)
        }}
        onChange={(e) => {
          // Do not assign input.value here — that reintroduces the WebKit bug.
          // Keep defaultValue "" so iOS Clear empties instead of restoring
          // a stale attribute value.
          e.currentTarget.defaultValue = ""
          onChange?.(e)
        }}
        onBlur={(e) => {
          const input = e.currentTarget
          const next = normalizeTimeValue(input.value)
          if (input.value !== next) {
            input.value = next
          }
          input.defaultValue = ""
          setFocused(false)
          // Commit normalized value to parent after editing finishes.
          onChange?.(e)
          onBlur?.(e)
        }}
        className="tt-time-field-input h-full min-h-[2.5rem] w-full cursor-text border-0 bg-transparent p-2 pr-11 text-white outline-none [color-scheme:dark]"
      />
      <button
        type="button"
        className="tt-time-field-icon"
        aria-label="Open time picker"
        tabIndex={-1}
        onMouseDown={(e) => {
          // Preserve user activation; avoid stealing focus before showPicker.
          e.preventDefault()
        }}
        onPointerDown={(e) => {
          e.preventDefault()
        }}
        onClick={openClock}
      >
        <span aria-hidden="true">🕒</span>
      </button>
    </div>
  )
}
