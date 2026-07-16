"use client"

import { useEffect, useRef } from "react"
import { cn } from "./cn"

function supportsShowPicker(input: HTMLInputElement): boolean {
  return typeof input.showPicker === "function"
}

/**
 * Safari (macOS/iOS) exposes showPicker for date/time but has a known bug:
 * the picker often cannot be dismissed by clicking outside. Prefer the native
 * indicator / focus path on WebKit; keep showPicker for Chromium only.
 */
export function isSafariWebKit(): boolean {
  if (typeof navigator === "undefined") return false
  const ua = navigator.userAgent
  if (/CriOS|FxiOS|EdgiOS|OPiOS/i.test(ua)) return false
  return /Safari/i.test(ua) && !/Chrome|Chromium|Android/i.test(ua)
}

export function canUseProgrammaticShowPicker(
  input: HTMLInputElement | null | undefined
): boolean {
  if (!input || !supportsShowPicker(input)) return false
  return !isSafariWebKit()
}

/**
 * Chromium helper: open via showPicker, blurring first when already focused
 * so a second click reopens. Never call on Safari — use the native indicator.
 */
export function openNativeDatePicker(input: HTMLInputElement | null | undefined) {
  if (!canUseProgrammaticShowPicker(input) || !input) return

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

/**
 * Open a time picker from a direct user gesture (e.g. clock button).
 *
 * Unlike date fields, Safari macOS supports showPicker for `type="time"` and
 * users need the clock UI when they tap the icon. iOS often lacks showPicker
 * for time — fall back to focus/click so the native wheel still opens.
 * Must be called synchronously from a click/pointer handler (user activation).
 */
export function openNativeTimePicker(input: HTMLInputElement | null | undefined) {
  if (!input) return

  if (supportsShowPicker(input)) {
    try {
      input.showPicker()
      return
    } catch {
      // NotAllowedError / unsupported context — fall through.
    }
  }

  try {
    input.focus({ preventScroll: true })
  } catch {
    input.focus()
  }
  try {
    input.click()
  } catch {
    // ignore
  }
}

function useDismissNativeTemporalField(
  inputRef: React.RefObject<HTMLInputElement | null>
) {
  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return
      const input = inputRef.current
      if (!input || document.activeElement !== input) return
      e.preventDefault()
      input.blur()
    }

    window.addEventListener("keydown", onKeyDown)
    return () => {
      window.removeEventListener("keydown", onKeyDown)
    }
  }, [inputRef])
}

export { useDismissNativeTemporalField }

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
  useDismissNativeTemporalField(inputRef)

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
        type="date"
        onFocus={(e) => {
          onFocus?.(e)
        }}
        onClick={(e) => {
          onClick?.(e)
          // Chromium only — Safari showPicker traps outside-click dismissal.
          const input = inputRef.current
          if (input && canUseProgrammaticShowPicker(input)) {
            openNativeDatePicker(input)
          }
        }}
        onChange={(e) => {
          onChange?.(e)
          // Chromium: release focus so the next tap reopens cleanly.
          // Safari: blur after the native sheet applies the value so the form
          // is not left with a sticky focused temporal control.
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
        className="tt-date-field-input w-full cursor-pointer border-0 bg-transparent text-white outline-none [color-scheme:dark]"
        {...props}
      />
      <span className="tt-date-field-icon text-gray-300" aria-hidden="true">
        📅
      </span>
    </div>
  )
}
