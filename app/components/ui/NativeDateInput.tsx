"use client"

import { useRef } from "react"
import { cn } from "./cn"

export function openNativeDatePicker(input: HTMLInputElement | null | undefined) {
  if (!input) return
  try {
    input.showPicker()
  } catch {
    input.focus()
  }
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
  ...props
}: NativeDateInputProps) {
  const inputRef = useRef<HTMLInputElement>(null)

  function handleOpen() {
    openNativeDatePicker(inputRef.current)
  }

  return (
    <div
      className={cn(
        "tt-date-field w-full min-w-0 cursor-pointer rounded-xl border border-white/10 bg-black/30",
        className
      )}
      onClick={handleOpen}
    >
      <input
        ref={inputRef}
        id={id}
        type="date"
        onFocus={(e) => {
          onFocus?.(e)
          handleOpen()
        }}
        onClick={(e) => {
          onClick?.(e)
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
