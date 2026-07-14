"use client"

import { useRef } from "react"
import { cn } from "./cn"

function supportsShowPicker(input: HTMLInputElement): boolean {
  return typeof input.showPicker === "function"
}

/**
 * Chromium helper: open via showPicker, blurring first when already focused
 * so a second click reopens. iOS Safari has no reliable showPicker — rely on
 * the full-field ::-webkit-calendar-picker-indicator hit target instead.
 */
export function openNativeDatePicker(input: HTMLInputElement | null | undefined) {
  if (!input || !supportsShowPicker(input)) return

  const tryShowPicker = () => {
    try {
      input.showPicker()
    } catch {
      try {
        input.focus({ preventScroll: true })
      } catch {
        input.focus()
      }
    }
  }

  if (document.activeElement === input) {
    input.blur()
    requestAnimationFrame(() => {
      requestAnimationFrame(tryShowPicker)
    })
    return
  }

  tryShowPicker()
}

type NativeDateInputProps = Omit<
  React.InputHTMLAttributes<HTMLInputElement>,
  "type"
>

export default function NativeDateInput({
  className,
  id,
  onFocus,
  onClick,
  onChange,
  onBlur,
  ...props
}: NativeDateInputProps) {
  const inputRef = useRef<HTMLInputElement>(null)

  return (
    <div
      className={cn(
        "tt-date-field w-full min-w-0 cursor-pointer rounded-xl border border-white/10 bg-black/30",
        className
      )}
      onPointerDown={(e) => {
        // Tap on the box chrome (not the input): open via Chromium showPicker
        // or focus so iOS indicator receives the following activation.
        if (e.target !== e.currentTarget) return
        const input = inputRef.current
        if (!input) return
        if (supportsShowPicker(input)) {
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
        type="date"
        onFocus={(e) => {
          onFocus?.(e)
        }}
        onClick={(e) => {
          onClick?.(e)
          // Chromium: ensure reopen when already focused.
          // iOS: leave native full-field indicator alone — do not blur/re-click.
          const input = inputRef.current
          if (input && supportsShowPicker(input)) {
            openNativeDatePicker(input)
          }
        }}
        onChange={(e) => {
          onChange?.(e)
          // Release focus after selection so the next tap reopens cleanly.
          e.currentTarget.blur()
        }}
        onBlur={(e) => {
          onBlur?.(e)
        }}
        className="tt-date-field-input w-full cursor-pointer border-0 bg-transparent text-white outline-none [color-scheme:dark]"
        {...props}
      />
      <span className="tt-date-field-icon text-gray-400" aria-hidden="true">
        📅
      </span>
    </div>
  )
}
