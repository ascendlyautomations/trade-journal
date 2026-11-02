"use client"

import CustomSelect from "@/app/components/CustomSelect"
import type { LeaderboardAccountTypeFilter } from "@/lib/leaderboardChart"
import {
  LEADERBOARD_AUDIENCE_OPTIONS,
  LEADERBOARD_BOOTSTRAP_TIMEFRAME_OPTIONS,
  LEADERBOARD_CATEGORY_OPTIONS,
  leaderboardTimeframeSelectValue,
  type LeaderboardBootstrapAudience,
  type LeaderboardBootstrapCategory,
  type LeaderboardPageTimeframe,
} from "@/lib/leaderboardBootstrap"

const CHIP_CLASS =
  "tt-mobile-web-hit-y min-h-8 flex-1 rounded-[10px] px-1.5 text-[12px] font-semibold transition"
const SELECT_CLASS =
  "tt-leaderboard-select-trigger flex w-full min-w-0 cursor-pointer items-center justify-between rounded-[10px] border border-white/10 bg-[#1e293b] px-3 py-2.5 text-left text-sm text-white"

type MobileWebLeaderboardFiltersProps = {
  audience: LeaderboardBootstrapAudience
  onAudienceChange: (value: LeaderboardBootstrapAudience) => void
  pageTimeframe: LeaderboardPageTimeframe
  onPageTimeframeChange: (value: LeaderboardPageTimeframe) => void
  category: LeaderboardBootstrapCategory
  onCategoryChange: (value: LeaderboardBootstrapCategory) => void
  accountTypeFilter: LeaderboardAccountTypeFilter
  onAccountTypeFilterChange: (value: LeaderboardAccountTypeFilter) => void
  usesRpcRankings: boolean
}

export default function MobileWebLeaderboardFilters({
  audience,
  onAudienceChange,
  pageTimeframe,
  onPageTimeframeChange,
  category,
  onCategoryChange,
  accountTypeFilter,
  onAccountTypeFilterChange,
  usesRpcRankings,
}: MobileWebLeaderboardFiltersProps) {
  const rpcTimeframes = LEADERBOARD_BOOTSTRAP_TIMEFRAME_OPTIONS.filter(
    (option) => option.timeframe.kind === "rpc"
  )
  const extraTimeframes = LEADERBOARD_BOOTSTRAP_TIMEFRAME_OPTIONS.filter(
    (option) => option.timeframe.kind === "legacy"
  )
  const selectedTimeframe = leaderboardTimeframeSelectValue(pageTimeframe)

  return (
    <div className="flex flex-col gap-3">
      <div
        className="grid grid-cols-3 overflow-hidden rounded-[10px] bg-[color:var(--tt-surface-nested,#1a222c)] p-0.5"
        role="group"
        aria-label="Audience"
      >
        {LEADERBOARD_AUDIENCE_OPTIONS.map((option) => {
          const selected = audience === option.value
          return (
            <button
              key={option.value}
              type="button"
              disabled={!usesRpcRankings}
              data-selected={selected ? "true" : "false"}
              onClick={() => onAudienceChange(option.value)}
              className={`tt-mobile-web-hit-y min-h-9 rounded-[8px] text-[13px] font-semibold disabled:opacity-50 ${
                selected
                  ? "bg-[color:color-mix(in_srgb,var(--tt-text)_12%,transparent)] text-[color:var(--tt-text,#f0f3f6)]"
                  : "text-[color:var(--tt-text-muted,#c0cad6)]"
              }`}
            >
              {option.label}
            </button>
          )
        })}
      </div>

      <div
        className="flex gap-1"
        role="group"
        aria-label="Timeframe"
      >
        {rpcTimeframes.map((option) => {
          const value = leaderboardTimeframeSelectValue(option.timeframe)
          const selected = selectedTimeframe === value
          return (
            <button
              key={value}
              type="button"
              onClick={() => onPageTimeframeChange(option.timeframe)}
              className={`${CHIP_CLASS} ${
                selected
                  ? "bg-[color:color-mix(in_srgb,var(--tt-accent)_22%,transparent)] text-[color:var(--tt-text,#f0f3f6)]"
                  : "bg-[color:var(--tt-surface-nested,#1a222c)] text-[color:var(--tt-text-muted,#c0cad6)]"
              }`}
            >
              {option.label}
            </button>
          )
        })}
      </div>

      <div className="flex gap-1">
        {extraTimeframes.map((option) => {
          const value = leaderboardTimeframeSelectValue(option.timeframe)
          const selected = selectedTimeframe === value
          return (
            <button
              key={value}
              type="button"
              onClick={() => onPageTimeframeChange(option.timeframe)}
              className={`tt-mobile-web-hit-y min-h-8 rounded-[10px] px-3 text-[12px] font-semibold ${
                selected
                  ? "bg-[color:color-mix(in_srgb,var(--tt-accent)_22%,transparent)] text-[color:var(--tt-text,#f0f3f6)]"
                  : "bg-[color:var(--tt-surface-nested,#1a222c)] text-[color:var(--tt-text-muted,#c0cad6)]"
              }`}
            >
              {option.label}
            </button>
          )
        })}
      </div>

      <CustomSelect
        value={category}
        onChange={(val) => onCategoryChange(val as LeaderboardBootstrapCategory)}
        disabled={!usesRpcRankings}
        className="w-full min-w-0"
        triggerClassName={SELECT_CLASS}
        options={LEADERBOARD_CATEGORY_OPTIONS.map((option) => ({
          label: option.label,
          value: option.value,
        }))}
      />

      <CustomSelect
        value={accountTypeFilter}
        onChange={(val) =>
          onAccountTypeFilterChange(val as LeaderboardAccountTypeFilter)
        }
        className="w-full min-w-0"
        triggerClassName={SELECT_CLASS}
        options={[
          { label: "All Accounts", value: "all" },
          { label: "Live", value: "live" },
          { label: "Funded", value: "funded" },
          { label: "Eval", value: "eval" },
        ]}
      />
    </div>
  )
}
