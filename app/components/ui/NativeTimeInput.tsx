"use client"

import { useEffect, useRef } from "react"
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
 * - Chromium: optional showPicker on field chrome / click (reliable dismiss).
 * - Safari macOS/iOS: native type=time only — never call showPicker (traps UX).
 * Users can type HH:MM or use the native control affordance.
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
          const input = inputRef.current
          if (input && canUseProgrammaticShowPicker(input)) {
            openNativeDatePicker(input)
          }
        }}
        onChange={(e) => {
          onChange?.(e)
          const input = e.currentTarget
          if (canUseProgrammaticShowPicker(input)) {
            input.blur()
          } else {
            requestAnimationFrame(() => {
              if (document.activeElement === input) input.blur()
            })
          }
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
