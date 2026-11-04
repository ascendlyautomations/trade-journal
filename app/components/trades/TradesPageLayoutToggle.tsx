"use client"

import { memo } from "react"
import { Images, List } from "lucide-react"

export type TradesPageLayoutView = "list" | "photos"

type TradesPageLayoutToggleProps = {
  value: TradesPageLayoutView
  onChange: (value: TradesPageLayoutView) => void
}

function TradesPageLayoutToggle({
  value,
  onChange,
}: TradesPageLayoutToggleProps) {
  const options: {
    id: TradesPageLayoutView
    label: string
    Icon: typeof List
  }[] = [
    { id: "list", label: "List", Icon: List },
    { id: "photos", label: "Photos", Icon: Images },
  ]

  return (
    <div
      role="tablist"
      aria-label="Trades layout"
      className="inline-flex shrink-0 rounded-lg border border-white/10 bg-white/5 p-0.5"
    >
      {options.map(({ id, label, Icon }) => {
        const selected = value === id
        return (
          <button
            key={id}
            type="button"
            role="tab"
            aria-selected={selected}
            title={label}
            onClick={() => onChange(id)}
            className={`inline-flex h-[30px] items-center gap-1.5 rounded-md px-2.5 text-xs font-semibold transition-colors ${
              selected
                ? "bg-blue-500 text-white shadow-sm"
                : "text-gray-400 hover:text-gray-200"
            }`}
          >
            <Icon className="h-3.5 w-3.5" strokeWidth={2} aria-hidden />
            <span>{label}</span>
          </button>
        )
      })}
    </div>
  )
}

export default memo(TradesPageLayoutToggle)
