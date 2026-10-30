"use client"

import { memo, type ComponentType } from "react"
import {
  BarChart3,
  Calendar,
  LayoutGrid,
  PlaySquare,
  TrendingUp,
  Trophy,
} from "lucide-react"

export type ProfileTab =
  | "trades"
  | "reels"
  | "posts"
  | "calendar"
  | "stats"
  | "achievements"

type ProfileTabsProps = {
  activeTab: ProfileTab
  onTabChange: (tab: ProfileTab) => void
}

const tabs: Array<{
  id: ProfileTab
  label: string
  Icon: ComponentType<{ className?: string; strokeWidth?: number }>
  ariaLabel?: string
}> = [
  { id: "trades", label: "Trades", Icon: TrendingUp },
  { id: "reels", label: "Clips", Icon: PlaySquare },
  { id: "posts", label: "Posts", Icon: LayoutGrid },
  { id: "stats", label: "Stats", Icon: BarChart3, ariaLabel: "Stats" },
  { id: "calendar", label: "Calendar", Icon: Calendar, ariaLabel: "Calendar" },
  {
    id: "achievements",
    label: "Achievements",
    Icon: Trophy,
    ariaLabel: "Achievements",
  },
]

function ProfileTabs({
  activeTab,
  onTabChange,
}: ProfileTabsProps) {
  return (
    <div className="mt-0 flex justify-around border-b border-white/10 sm:mt-6 sm:justify-start sm:gap-6 sm:pb-2">
      {tabs.map(({ id, label, Icon, ariaLabel }) => (
        <button
          key={id}
          type="button"
          aria-label={ariaLabel ?? label}
          className={`border-b-2 py-1.5 text-sm font-medium sm:py-0 max-md:min-h-11 max-md:min-w-0 max-md:flex-1 ${
            activeTab === id
              ? "border-blue-400 text-white sm:border-blue-500 sm:pb-1"
              : "border-transparent text-gray-300 sm:border-b-0 sm:text-gray-400"
          }`}
          onClick={() => onTabChange(id)}
        >
          <span className="hidden md:inline">{label}</span>
          <span className="md:hidden inline-flex items-center justify-center" aria-hidden>
            <Icon
              className="h-5 w-5"
              strokeWidth={activeTab === id ? 2.25 : 1.75}
            />
          </span>
        </button>
      ))}
    </div>
  )
}

export default memo(ProfileTabs)
