"use client"

import { useEffect, useRef, useState } from "react"

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

export default function CustomSelect({
  value,
  onChange,
  options,
  placeholder = "Select an option",
}: Props) {
  const [open, setOpen] = useState(false)
  const rootRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    function handleOutsideClick(event: MouseEvent) {
      if (!rootRef.current) return
      if (!rootRef.current.contains(event.target as Node)) {
        setOpen(false)
      }
    }

    document.addEventListener("mousedown", handleOutsideClick)
    return () => document.removeEventListener("mousedown", handleOutsideClick)
  }, [])

  const selected = options.find((opt) => opt.value === value)

  return (
    <div ref={rootRef} className="relative w-full">
      <div
        role="button"
        tabIndex={0}
        onClick={() => setOpen((prev) => !prev)}
        onKeyDown={(e) => {
          if (e.key === "Enter" || e.key === " ") {
            e.preventDefault()
            setOpen((prev) => !prev)
          }
        }}
        className="flex w-full cursor-pointer items-center justify-between rounded-xl border border-white/10 bg-[#0f172a] px-4 py-3 text-sm"
      >
        <span className={selected ? "text-white" : "text-gray-400"}>
          {selected?.label ?? placeholder}
        </span>
        <span className="ml-2 shrink-0 text-gray-400">▾</span>
      </div>

      {open ? (
        <div className="absolute z-50 mt-1 w-full overflow-hidden rounded-xl border border-white/10 bg-[#0f172a] shadow-lg">
          {options.map((opt) => (
            <button
              key={opt.value}
              type="button"
              onClick={() => {
                onChange(opt.value)
                setOpen(false)
              }}
              className="w-full px-4 py-2.5 text-left text-sm text-white hover:bg-[#1f2937]"
            >
              {opt.label}
            </button>
          ))}
        </div>
      ) : null}
    </div>
  )
}
