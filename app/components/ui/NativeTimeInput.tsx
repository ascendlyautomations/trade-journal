"use client"

import { useRef } from "react"
import { cn } from "./cn"
import {
  canUseProgrammaticShowPicker,
  openNativeDatePicker,
  useDismissNativeTemporalField,
} from "./NativeDateInput"

type NativeTimeInputProps = Omit<
  React.InputHTMLAttributes<HTMLInputElement>,
  "type"
>

/**
 * Cross-browser time field for trade forms.
 *
 * Safari note: never stretch the calendar-picker-indicator over the whole
 * field and never blur() inside onChange — both block Safari's editable
 * HH:MM segments during manual entry.
 */
export default function NativeTimeInput({
  className,
  id,
  onFocus,
  onClick,
  onChange,
  onBlur,
  step = 60,
  ...props
}: NativeTimeInputProps) {
  const inputRef = useRef<HTMLInputElement>(null)
  useDismissNativeTemporalField(inputRef)

  return (
    <div
      className={cn(
        "tt-time-field w-full min-w-0 cursor-pointer rounded border border-white/10 bg-[#0f172a]",
        className
      )}
      onPointerDown={(e) => {
        // Only when clicking empty chrome around the input (not the input itself).
        if (e.target !== e.currentTarget) return
        const input = inputRef.current
        if (!input) return
        if (canUseProgrammaticShowPicker(input)) {
          e.preventDefault()
          openNativeDatePicker(input)
        } else {
          try {
            input.focus({ preventScroll: true })
          } catch {
            input.focus()
          }
        }
      }}
    >
      <input
        ref={inputRef}
        id={id}
        type="time"
        step={step}
        onFocus={(e) => {
          onFocus?.(e)
        }}
        onClick={(e) => {
          onClick?.(e)
          // Chromium only: optional picker open. Do not call on Safari —
          // showPicker / click interference breaks segment editing.
          const input = inputRef.current
          if (input && canUseProgrammaticShowPicker(input)) {
            // Only open picker when the click lands on the indicator region
            // (right edge). Clicks on HH:MM segments must remain editable.
            const rect = input.getBoundingClientRect()
            const nearIcon = e.clientX >= rect.right - 40
            if (nearIcon) {
              openNativeDatePicker(input)
            }
          }
        }}
        onChange={(e) => {
          // Do not blur here — Safari fires change while editing segments;
          // blurring aborts manual entry. Leave focus until the user leaves.
          onChange?.(e)
        }}
        onBlur={(e) => {
          onBlur?.(e)
        }}
        className="tt-time-field-input h-full min-h-[2.5rem] w-full cursor-pointer border-0 bg-transparent p-2 pr-10 text-white outline-none [color-scheme:dark]"
        {...props}
      />
      <span className="tt-time-field-icon text-gray-300" aria-hidden="true">
        🕒
      </span>
    </div>
  )
}
