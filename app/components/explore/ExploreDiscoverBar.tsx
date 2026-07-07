"use client"

import {
  EXPLORE_CATEGORY_TABS,
  type ExploreDiscoverFilters,
  type ExploreExperienceFilter,
  type ExploreSessionFilter,
  type ExploreTradingStyleFilter,
} from "@/lib/exploreFilters"

const CHIP_BASE =
  "shrink-0 rounded-full border px-3 py-1.5 text-xs font-medium transition"

function chipClass(active: boolean) {
  return (
    CHIP_BASE +
    (active
      ? " border-blue-400/40 bg-blue-500/20 text-blue-100"
      : " border-white/10 bg-black/20 text-gray-300 hover:border-white/20 hover:bg-white/5")
  )
}

type ExploreDiscoverBarProps = {
  filters: ExploreDiscoverFilters
  onChange: (patch: Partial<ExploreDiscoverFilters>) => void
  availability: {
    session: boolean
    experience: boolean
    tradingStyle: boolean
  }
}

const SESSION_OPTIONS: ReadonlyArray<{
  value: ExploreSessionFilter
  label: string
}> = [
  { value: "all", label: "All Sessions" },
  { value: "NY", label: "NY Session" },
  { value: "London", label: "London" },
  { value: "Asia", label: "Asia" },
]

const EXPERIENCE_OPTIONS: ReadonlyArray<{
  value: ExploreExperienceFilter
  label: string
}> = [
  { value: "all", label: "All Experience" },
  { value: "beginner", label: "Beginner" },
  { value: "intermediate", label: "Intermediate" },
  { value: "advanced", label: "Advanced" },
]

const STYLE_OPTIONS: ReadonlyArray<{
  value: ExploreTradingStyleFilter
  label: string
}> = [
  { value: "all", label: "All Styles" },
  { value: "scalper", label: "Scalper" },
  { value: "day_trader", label: "Day Trader" },
  { value: "swing_trader", label: "Swing Trader" },
  { value: "position_trader", label: "Position Trader" },
]

export default function ExploreDiscoverBar({
  filters,
  onChange,
  availability,
}: ExploreDiscoverBarProps) {
  const showSubFilters =
    availability.session ||
    availability.experience ||
    availability.tradingStyle

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        {EXPLORE_CATEGORY_TABS.map((tab) => (
          <button
            key={tab.value}
            type="button"
            onClick={() => onChange({ category: tab.value })}
            className={chipClass(filters.category === tab.value)}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {showSubFilters ? (
        <div className="space-y-2 border-t border-white/10 pt-3">
          {availability.session ? (
            <FilterRow label="Session">
              {SESSION_OPTIONS.map((option) => (
                <button
                  key={option.value}
                  type="button"
                  onClick={() => onChange({ session: option.value })}
                  className={chipClass(filters.session === option.value)}
                >
                  {option.label}
                </button>
              ))}
            </FilterRow>
          ) : null}

          {availability.experience ? (
            <FilterRow label="Experience">
              {EXPERIENCE_OPTIONS.map((option) => (
                <button
                  key={option.value}
                  type="button"
                  onClick={() => onChange({ experience: option.value })}
                  className={chipClass(filters.experience === option.value)}
                >
                  {option.label}
                </button>
              ))}
            </FilterRow>
          ) : null}

          {availability.tradingStyle ? (
            <FilterRow label="Style">
              {STYLE_OPTIONS.map((option) => (
                <button
                  key={option.value}
                  type="button"
                  onClick={() => onChange({ tradingStyle: option.value })}
                  className={chipClass(filters.tradingStyle === option.value)}
                >
                  {option.label}
                </button>
              ))}
            </FilterRow>
          ) : null}
        </div>
      ) : null}
    </div>
  )
}

function FilterRow({
  label,
  children,
}: {
  label: string
  children: React.ReactNode
}) {
  return (
    <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
      <span className="w-20 shrink-0 text-[11px] font-semibold uppercase tracking-wide text-gray-500">
        {label}
      </span>
      <div className="flex min-w-0 flex-1 flex-wrap gap-2">
        {children}
      </div>
    </div>
  )
}
