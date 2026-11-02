"use client"

import { memo, type ComponentType } from "react"
import type { ProfileTab } from "@/app/components/profile/ProfileTabs"
import {
  BarChart3,
  LayoutGrid,
  PlaySquare,
  TrendingUp,
  Trophy,
} from "lucide-react"

type MobileWebProfileSectionPickerProps = {
  activeTab: ProfileTab
  onTabChange: (tab: ProfileTab) => void
}

const TABS: Array<{
  id: ProfileTab
  label: string
  Icon: ComponentType<{ className?: string; strokeWidth?: number }>
}> = [
  { id: "trades", label: "Trades", Icon: TrendingUp },
  { id: "posts", label: "Posts", Icon: LayoutGrid },
  { id: "reels", label: "Clips", Icon: PlaySquare },
  { id: "stats", label: "Stats", Icon: BarChart3 },
  { id: "achievements", label: "Achievements", Icon: Trophy },
]

function MobileWebProfileSectionPicker({
  activeTab,
  onTabChange,
}: MobileWebProfileSectionPickerProps) {
  return (
    <div
      className="flex justify-around px-2"
      role="tablist"
      aria-label="Profile sections"
    >
      {TABS.map(({ id, label, Icon }) => {
        const selected = activeTab === id
        return (
          <button
            key={id}
            type="button"
            role="tab"
            aria-selected={selected}
            aria-label={label}
            onClick={() => onTabChange(id)}
            className="relative flex min-h-11 min-w-0 flex-1 items-center justify-center text-[color:var(--tt-text,#1f2328)]"
          >
            <Icon
              className={`h-5 w-5 ${
                selected
                  ? "text-[#4EC4E0]"
                  : "text-[color:var(--tt-text,#1f2328)]"
              }`}
              strokeWidth={selected ? 2.25 : 1.75}
              aria-hidden
            />
            {selected ? (
              <span
                className="absolute inset-x-2 bottom-0 h-0.5 rounded-full bg-[#4EC4E0]"
                aria-hidden
              />
            ) : null}
          </button>
        )
      })}
    </div>
  )
}

export default memo(MobileWebProfileSectionPicker)
