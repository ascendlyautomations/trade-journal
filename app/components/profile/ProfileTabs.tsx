"use client"

import { memo } from "react"

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
  mobileLabel?: string
  ariaLabel?: string
}> = [
  { id: "trades", label: "Trades" },
  { id: "reels", label: "Clips" },
  { id: "posts", label: "Posts" },
  { id: "stats", label: "Stats", mobileLabel: "📊", ariaLabel: "Stats" },
  {
    id: "calendar",
    label: "Calendar",
    mobileLabel: "📅",
    ariaLabel: "Calendar",
  },
  {
    id: "achievements",
    label: "Achievements",
    mobileLabel: "🏆",
    ariaLabel: "Achievements",
  },
]

function ProfileTabs({
  activeTab,
  onTabChange,
}: ProfileTabsProps) {
  return (
    <div className="mt-0 flex justify-around border-b border-white/10 sm:mt-6 sm:justify-start sm:gap-6 sm:pb-2">
      {tabs.map(({ id, label, mobileLabel, ariaLabel }) => (
        <button
          key={id}
          type="button"
          aria-label={ariaLabel}
          className={`border-b-2 py-1.5 text-sm font-medium sm:py-0 ${
            activeTab === id
              ? "border-blue-400 text-white sm:border-blue-500 sm:pb-1"
              : "border-transparent text-gray-300 sm:border-b-0 sm:text-gray-400"
          }`}
          onClick={() => onTabChange(id)}
        >
          {mobileLabel ? (
            <>
              <span className="hidden sm:inline">{label}</span>
              <span className="sm:hidden" aria-hidden>
                {mobileLabel}
              </span>
            </>
          ) : (
            label
          )}
        </button>
      ))}
    </div>
  )
}

export default memo(ProfileTabs)
