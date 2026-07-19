"use client"

import type { Dispatch, SetStateAction } from "react"
import type { GearDraftState } from "./dashboardGearTypes"
import {
  DASHBOARD_GEAR_SECTION_TITLE,
  finalizeDrawdownLimitInput,
  formatDrawdownLimitForDisplay,
  sanitizeDrawdownLimitInput,
} from "./dashboardGearUtils"
import { DASHBOARD_MOBILE_GEAR_BTN_CLASS } from "./dashboardHeaderMobileUi"

export type DashboardGearSettingsProps = {
  showControls: boolean
  onToggleShowControls: () => void
  gearDraft: GearDraftState | null
  setGearDraft: Dispatch<SetStateAction<GearDraftState | null>>
  ddInputFocused: boolean
  setDdInputFocused: (focused: boolean) => void
  savingGearSettings: boolean
  hasUser: boolean
  onSaveGear: () => void
  onCancelGear: () => void
}

export default function DashboardGearSettings({
  showControls,
  onToggleShowControls,
  gearDraft,
  setGearDraft,
  ddInputFocused,
  setDdInputFocused,
  savingGearSettings,
  hasUser,
  onSaveGear,
  onCancelGear,
}: DashboardGearSettingsProps) {
  return (
    <div className="relative z-[100] shrink-0 dashboard-controls">
      <button
        type="button"
        onClick={onToggleShowControls}
        className={DASHBOARD_MOBILE_GEAR_BTN_CLASS}
        aria-label="Dashboard controls"
        aria-expanded={showControls}
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="20"
          height="20"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          aria-hidden
        >
          <path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z" />
          <circle cx="12" cy="12" r="3" />
        </svg>
      </button>

      {showControls ? (
        <div className="absolute right-0 top-full z-[100] mt-2 w-[min(22rem,calc(100vw-1.5rem))] max-h-[min(85vh,36rem)] overflow-y-auto rounded-xl border border-white/10 bg-[#0f172a]/95 p-4 shadow-xl shadow-black/40 backdrop-blur-md">
          <p className="mb-3 border-b border-white/10 pb-2 text-sm font-semibold text-white">
            Dashboard preferences
          </p>

          {!gearDraft ? (
            <p className="text-xs text-gray-400">Loading…</p>
          ) : (
            <>
              <div className="mb-3 space-y-2 rounded-lg border border-white/10 bg-black/25 p-3">
                <p className={DASHBOARD_GEAR_SECTION_TITLE}>Display</p>
                <label className="flex cursor-pointer items-center justify-between gap-2 text-sm text-gray-200">
                  <span>Performance charts</span>
                  <input
                    type="checkbox"
                    className="accent-blue-500"
                    checked={gearDraft.showEquity && gearDraft.showDrawdown}
                    onChange={(e) => {
                      const on = e.target.checked
                      setGearDraft((d) =>
                        d ? { ...d, showEquity: on, showDrawdown: on } : d
                      )
                    }}
                  />
                </label>
                <label className="flex cursor-pointer items-center justify-between gap-2 text-sm text-gray-200">
                  <span>Insights overview</span>
                  <input
                    type="checkbox"
                    className="accent-blue-500"
                    checked={gearDraft.showInsights}
                    onChange={() =>
                      setGearDraft((d) =>
                        d ? { ...d, showInsights: !d.showInsights } : d
                      )
                    }
                  />
                </label>
                <label className="flex cursor-pointer items-center justify-between gap-2 text-sm text-gray-200">
                  <span>Session chart</span>
                  <input
                    type="checkbox"
                    className="accent-blue-500"
                    checked={gearDraft.showSessions}
                    onChange={() =>
                      setGearDraft((d) =>
                        d ? { ...d, showSessions: !d.showSessions } : d
                      )
                    }
                  />
                </label>
                <label className="flex cursor-pointer items-center justify-between gap-2 text-sm text-gray-200">
                  <span>Setups & behavior tips</span>
                  <input
                    type="checkbox"
                    className="accent-blue-500"
                    checked={
                      gearDraft.showBestSetup &&
                      gearDraft.showWorstSetup &&
                      gearDraft.showWarnings
                    }
                    onChange={(e) => {
                      const on = e.target.checked
                      setGearDraft((d) =>
                        d
                          ? {
                              ...d,
                              showBestSetup: on,
                              showWorstSetup: on,
                              showWarnings: on,
                            }
                          : d
                      )
                    }}
                  />
                </label>
              </div>

              <div className="mb-3 rounded-lg border border-white/10 bg-black/25 p-3">
                <p className={DASHBOARD_GEAR_SECTION_TITLE}>Risk</p>
                <p className="mt-1 text-[11px] leading-snug text-gray-400">
                  Max drawdown from equity peak. Leave blank for no limit.
                </p>
                <label htmlFor="dashboard-max-dd" className="sr-only">
                  Max drawdown limit
                </label>
                <input
                  id="dashboard-max-dd"
                  type="text"
                  inputMode="decimal"
                  autoComplete="off"
                  placeholder="$0"
                  disabled={!hasUser}
                  value={formatDrawdownLimitForDisplay(
                    gearDraft.drawdownLimit,
                    ddInputFocused
                  )}
                  onFocus={() => setDdInputFocused(true)}
                  onBlur={() => {
                    setDdInputFocused(false)
                    setGearDraft((d) =>
                      d
                        ? {
                            ...d,
                            drawdownLimit: finalizeDrawdownLimitInput(
                              d.drawdownLimit
                            ),
                          }
                        : d
                    )
                  }}
                  onChange={(e) => {
                    const next = sanitizeDrawdownLimitInput(e.target.value)
                    setGearDraft((d) => (d ? { ...d, drawdownLimit: next } : d))
                  }}
                  className="mt-2 w-full rounded-lg border border-white/10 bg-[#020617] px-3 py-2 text-sm text-white tabular-nums placeholder:text-gray-400 focus:border-blue-400/50 focus:outline-none focus:ring-1 focus:ring-blue-400/40 disabled:opacity-50"
                />
              </div>

              <div className="mt-1 border-t border-white/10 pt-3">
                <div className="flex gap-2">
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation()
                      onSaveGear()
                    }}
                    disabled={savingGearSettings || !hasUser}
                    className="flex-1 rounded-lg bg-blue-500 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:bg-blue-500"
                  >
                    {savingGearSettings ? "Saving…" : "Save"}
                  </button>
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation()
                      onCancelGear()
                    }}
                    disabled={savingGearSettings}
                    className="flex-1 rounded-lg border border-white/15 bg-white/5 py-2.5 text-sm font-medium text-gray-200 transition hover:bg-white/10 disabled:opacity-50"
                  >
                    Cancel
                  </button>
                </div>
                <p className="mt-2 text-center text-[10px] text-gray-400">
                  Save applies defaults, display options, and your drawdown limit.
                </p>
              </div>
            </>
          )}
        </div>
      ) : null}
    </div>
  )
}
