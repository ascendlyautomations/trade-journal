"use client"

import { useLayoutEffect, useState } from "react"
import {
  WEB_APPEARANCE_CHANGE_EVENT,
  type WebAppearance,
  readWebAppearance,
  writeWebAppearance,
} from "@/lib/webAppearance"

const OPTIONS: {
  id: WebAppearance
  label: string
  description: string
  badge?: string
}[] = [
  {
    id: "dark",
    label: "Dark",
    description: "Current TradeTraxs dark appearance",
    badge: "Default",
  },
  {
    id: "light",
    label: "Light",
    description: "Bright high-contrast appearance",
  },
  {
    id: "og",
    label: "TradeTraxs OG",
    description: "Original TradeTraxs blue/green appearance",
  },
]

export default function AppearanceSettingsSection() {
  const [value, setValue] = useState<WebAppearance>("dark")

  useLayoutEffect(() => {
    setValue(readWebAppearance())
    function sync() {
      setValue(readWebAppearance())
    }
    window.addEventListener(WEB_APPEARANCE_CHANGE_EVENT, sync)
    window.addEventListener("storage", sync)
    return () => {
      window.removeEventListener(WEB_APPEARANCE_CHANGE_EVENT, sync)
      window.removeEventListener("storage", sync)
    }
  }, [])

  return (
    <div className="space-y-3" role="radiogroup" aria-label="Appearance">
      {OPTIONS.map((option) => {
        const selected = value === option.id
        return (
          <button
            key={option.id}
            type="button"
            role="radio"
            aria-checked={selected}
            onClick={() => {
              writeWebAppearance(option.id)
              setValue(option.id)
            }}
            className={`w-full rounded-xl border px-4 py-3 text-left transition ${
              selected
                ? "border-blue-400/40 bg-white/15 ring-1 ring-blue-400/50"
                : "border-white/10 bg-white/5 hover:bg-white/10"
            }`}
          >
            <span className="flex items-center gap-2">
              <span className="font-medium text-white">{option.label}</span>
              {option.badge ? (
                <span className="rounded-full border border-white/10 px-2 py-0.5 text-[10px] uppercase tracking-wide text-gray-400">
                  {option.badge}
                </span>
              ) : null}
            </span>
            <span className="mt-1 block text-sm text-gray-400">{option.description}</span>
          </button>
        )
      })}
    </div>
  )
}
