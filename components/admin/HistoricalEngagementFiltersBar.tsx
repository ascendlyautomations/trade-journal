"use client"

import {
  DEFAULT_HISTORICAL_ENGAGEMENT_QUERY,
  type HistoricalActivityFilter,
  type HistoricalEngagementQuery,
  type HistoricalRangePreset,
  historicalQueryLabel,
  validateHistoricalEngagementQuery,
} from "@/lib/adminHistoricalEngagementFilters"

const PRESET_OPTIONS: { id: HistoricalRangePreset; label: string }[] = [
  { id: 30, label: "30D" },
  { id: 90, label: "90D" },
  { id: 180, label: "6M" },
  { id: 365, label: "1Y" },
  { id: "custom", label: "Custom" },
]

const ACTIVITY_OPTIONS: { id: HistoricalActivityFilter; label: string }[] = [
  { id: "all", label: "All activity" },
  { id: "trading", label: "Trading" },
  { id: "social", label: "Social" },
]

export function HistoricalEngagementFiltersBar({
  query,
  onChange,
}: {
  query: HistoricalEngagementQuery
  onChange: (next: HistoricalEngagementQuery) => void
}) {
  const validation = validateHistoricalEngagementQuery(query)

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-xs font-medium uppercase tracking-wide text-gray-400">Range</span>
        <div className="flex flex-wrap rounded-lg border border-white/10 bg-black/20 p-1">
          {PRESET_OPTIONS.map((opt) => (
            <button
              key={String(opt.id)}
              type="button"
              onClick={() =>
                onChange({
                  ...query,
                  preset: opt.id,
                  customStartDate: opt.id === "custom" ? query.customStartDate : null,
                  customEndDate: opt.id === "custom" ? query.customEndDate : null,
                })
              }
              className={`rounded-md px-3 py-1 text-sm ${
                query.preset === opt.id ? "bg-white/15 text-white" : "text-gray-400 hover:text-gray-200"
              }`}
            >
              {opt.label}
            </button>
          ))}
        </div>
      </div>

      {query.preset === "custom" ? (
        <div className="flex flex-wrap items-end gap-3">
          <label className="flex flex-col gap-1 text-xs text-gray-400">
            Start (UTC)
            <input
              type="date"
              value={query.customStartDate ?? ""}
              onChange={(e) => onChange({ ...query, customStartDate: e.target.value || null })}
              className="rounded-md border border-white/10 bg-black/30 px-2 py-1 text-sm text-white"
            />
          </label>
          <label className="flex flex-col gap-1 text-xs text-gray-400">
            End (UTC)
            <input
              type="date"
              value={query.customEndDate ?? ""}
              onChange={(e) => onChange({ ...query, customEndDate: e.target.value || null })}
              className="rounded-md border border-white/10 bg-black/30 px-2 py-1 text-sm text-white"
            />
          </label>
        </div>
      ) : (
        <p className="text-xs text-gray-500">Period: {historicalQueryLabel(query)} ending today (UTC).</p>
      )}

      <div className="flex flex-wrap items-center gap-2">
        <span className="text-xs font-medium uppercase tracking-wide text-gray-400">Activity</span>
        <div className="flex flex-wrap rounded-lg border border-white/10 bg-black/20 p-1">
          {ACTIVITY_OPTIONS.map((opt) => (
            <button
              key={opt.id}
              type="button"
              onClick={() => onChange({ ...query, activityFilter: opt.id })}
              className={`rounded-md px-3 py-1 text-sm ${
                query.activityFilter === opt.id ? "bg-white/15 text-white" : "text-gray-400 hover:text-gray-200"
              }`}
            >
              {opt.label}
            </button>
          ))}
        </div>
      </div>

      {!validation.valid && query.preset === "custom" ? (
        <p className="text-xs text-amber-200">{validation.message}</p>
      ) : null}
    </div>
  )
}

export function defaultHistoricalQuery(): HistoricalEngagementQuery {
  return { ...DEFAULT_HISTORICAL_ENGAGEMENT_QUERY }
}