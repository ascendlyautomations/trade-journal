"use client"

import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react"
import { supabase } from "@/lib/supabaseClient"
import {
  TRADING_STYLE_OPTIONS,
  TRADING_PREFERENCE_SESSIONS,
  emptyTradingPreferenceGlobal,
  formatMinuteLabel,
  minutesToTimeInput,
  parseOptionalInteger,
  parseOptionalNonNegative,
  parseOptionalPositive,
  timeInputToMinutes,
  type TradingPreferenceAccountOverride,
  type TradingPreferenceGlobal,
  type TradingPreferenceSession,
  type TradingStyleId,
} from "@/lib/analytics/tradingPreferences"
import {
  TRADING_RULE_WEEKDAYS,
  weekdayDisplayLabel,
  type TradingRuleWeekday,
} from "@/lib/analytics/tradingRuleScope"
import TradingRuleScopeField from "@/app/components/settings/TradingRuleScopeField"
import {
  fetchTradingPreferenceGlobal,
  fetchTradingPreferenceOverrides,
  saveTradingPreferenceGlobal,
  saveTradingPreferenceOverride,
} from "@/lib/analytics/tradingPreferencesStore"
import { recordTradingPreferenceDiscovery } from "@/lib/analytics/preferenceDiscovery"
import TradingRuleTemplatesField from "@/app/components/settings/TradingRuleTemplatesField"
import type { TradingRuleTemplateSuggestion } from "@/lib/analytics/tradingRuleTemplates"
import type { TradingRulesDraftApi } from "@/app/components/settings/tradingRulesDraft"

type AccountOption = { id: string; name: string }

type Props = {
  userId: string | undefined
  onDraftApiChange?: (api: TradingRulesDraftApi | null) => void
}

const inputClass =
  "w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm text-white outline-none focus:border-blue-400/60"
const buttonClass =
  "rounded-lg border border-white/10 px-3 py-1.5 text-xs text-gray-200 hover:bg-white/10 disabled:opacity-40"

function Field({
  label,
  description,
  children,
}: {
  label: string
  description: string
  children: ReactNode
}) {
  return (
    <label className="block space-y-2">
      <span className="block text-sm font-medium text-white">{label}</span>
      <span className="block text-xs leading-5 text-gray-400">{description}</span>
      {children}
    </label>
  )
}

function emptyAccountOverride(
  userId: string,
  accountId: string
): TradingPreferenceAccountOverride {
  return {
    userId,
    accountId,
    overridesDailyLoss: false,
    dailyLossLimit: null,
    overridesDailyProfitTarget: false,
    dailyProfitTarget: null,
    overridesMaxDrawdownGoal: false,
    maxDrawdownGoal: null,
    updatedAt: null,
  }
}

export default function TradingAnalyticsPreferencesSection({
  userId,
  onDraftApiChange,
}: Props) {
  const [globalPrefs, setGlobalPrefs] = useState<TradingPreferenceGlobal | null>(null)
  const [savedGlobalPrefs, setSavedGlobalPrefs] = useState<TradingPreferenceGlobal | null>(null)
  const [overrides, setOverrides] = useState<TradingPreferenceAccountOverride[]>([])
  const [savedOverrides, setSavedOverrides] = useState<TradingPreferenceAccountOverride[]>([])
  const [accounts, setAccounts] = useState<AccountOption[]>([])
  const [accountId, setAccountId] = useState("")
  const [instrumentDraft, setInstrumentDraft] = useState("")
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (!userId) {
      setLoading(false)
      return
    }
    let cancelled = false
    setLoading(true)
    void (async () => {
      try {
        const [prefs, accountOverrides, accountRows] = await Promise.all([
          fetchTradingPreferenceGlobal(supabase, userId),
          fetchTradingPreferenceOverrides(supabase, userId),
          supabase
            .from("accounts")
            .select("id, name")
            .eq("user_id", userId)
            .order("name"),
        ])
        if (cancelled) return
        if (accountRows.error) throw accountRows.error
        setGlobalPrefs(prefs)
        setSavedGlobalPrefs(prefs)
        setOverrides(accountOverrides)
        setSavedOverrides(accountOverrides)
        const nextAccounts = (accountRows.data ?? []).map((row) => ({
          id: row.id,
          name: row.name,
        }))
        setAccounts(nextAccounts)
        setAccountId((current) => current || nextAccounts[0]?.id || "")
      } catch (cause) {
        if (!cancelled) {
          setError(cause instanceof Error ? cause.message : "Could not load preferences.")
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [userId])

  const selectedOverride =
    overrides.find((row) => row.accountId === accountId) ??
    (userId && accountId ? emptyAccountOverride(userId, accountId) : null)

  const hasUnsavedChanges = useMemo(() => {
    if (!savedGlobalPrefs || !globalPrefs) return false
    if (JSON.stringify(savedGlobalPrefs) !== JSON.stringify(globalPrefs)) return true
    const accountIds = new Set([
      ...savedOverrides.map((row) => row.accountId),
      ...overrides.map((row) => row.accountId),
    ])
    for (const id of accountIds) {
      if (!userId) continue
      const draft =
        overrides.find((row) => row.accountId === id) ?? emptyAccountOverride(userId, id)
      const saved =
        savedOverrides.find((row) => row.accountId === id) ?? emptyAccountOverride(userId, id)
      if (JSON.stringify(draft) !== JSON.stringify(saved)) return true
    }
    return false
  }, [globalPrefs, overrides, savedGlobalPrefs, savedOverrides, userId])

  useEffect(() => {
    if (!hasUnsavedChanges) return
    const onBeforeUnload = (event: BeforeUnloadEvent) => {
      event.preventDefault()
    }
    window.addEventListener("beforeunload", onBeforeUnload)
    return () => window.removeEventListener("beforeunload", onBeforeUnload)
  }, [hasUnsavedChanges])

  function updateGlobal(patch: Partial<TradingPreferenceGlobal>) {
    setGlobalPrefs((current) => {
      const base = current ?? emptyTradingPreferenceGlobal(userId ?? "")
      return { ...base, ...patch }
    })
  }

  const updateDraftOverride = useCallback(
    (next: TradingPreferenceAccountOverride) => {
      if (!userId) return
      setOverrides((current) => {
        const rest = current.filter((row) => row.accountId !== next.accountId)
        return [...rest, { ...next, userId }]
      })
    },
    [userId]
  )

  const saveAll = useCallback(async (): Promise<boolean> => {
    if (!userId || !globalPrefs) return true
    if (!hasUnsavedChanges) return true
    setSaving(true)
    setError(null)
    try {
      const persistedGlobal = await saveTradingPreferenceGlobal(supabase, globalPrefs)
      setGlobalPrefs(persistedGlobal)
      setSavedGlobalPrefs(persistedGlobal)

      let nextSaved = [...savedOverrides]
      for (const row of overrides) {
        const baseline =
          savedOverrides.find((item) => item.accountId === row.accountId) ??
          emptyAccountOverride(userId, row.accountId)
        if (JSON.stringify(baseline) === JSON.stringify(row)) continue
        const persisted = await saveTradingPreferenceOverride(supabase, row)
        nextSaved = nextSaved.filter((item) => item.accountId !== persisted.accountId)
        nextSaved.push(persisted)
      }
      setOverrides(nextSaved)
      setSavedOverrides(nextSaved)
      void recordTradingPreferenceDiscovery(supabase, userId, "completed").catch(() => undefined)
      return true
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not save preferences.")
      return false
    } finally {
      setSaving(false)
    }
  }, [globalPrefs, hasUnsavedChanges, overrides, savedOverrides, userId])

  const discardChanges = useCallback(() => {
    if (savedGlobalPrefs) setGlobalPrefs(savedGlobalPrefs)
    setOverrides(savedOverrides)
    setError(null)
  }, [savedGlobalPrefs, savedOverrides])

  useEffect(() => {
    if (!userId || loading || !globalPrefs) {
      onDraftApiChange?.(null)
      return
    }
    onDraftApiChange?.({
      hasUnsavedChanges,
      saveAll,
      discardChanges,
    })
    return () => onDraftApiChange?.(null)
  }, [
    discardChanges,
    globalPrefs,
    hasUnsavedChanges,
    loading,
    onDraftApiChange,
    saveAll,
    userId,
  ])

  if (!userId) return null
  if (loading || !globalPrefs) {
    return <p className="text-sm text-gray-400">Loading preferences…</p>
  }

  const prefs = globalPrefs

  return (
    <div className="space-y-6">
      <p className="text-sm leading-6 text-gray-300">
        Every answer is optional. A blank answer does not assume a trading style
        or turn on a personal rule. Edits stay as a draft until you tap Save.
      </p>
      {error ? (
        <p className="rounded-xl border border-red-400/30 bg-red-500/10 px-3 py-2 text-sm text-red-200">
          {error}
        </p>
      ) : null}

      <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-white/10 bg-black/30 px-4 py-3">
        <p className="text-sm text-gray-300">
          {hasUnsavedChanges
            ? "You have unsaved trading rules."
            : "All trading rules are saved."}
        </p>
        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            className={buttonClass}
            disabled={!hasUnsavedChanges || saving}
            onClick={() => discardChanges()}
          >
            Discard
          </button>
          <button
            type="button"
            className="rounded-lg border border-blue-400/50 bg-blue-500/20 px-4 py-1.5 text-xs font-semibold text-white hover:bg-blue-500/30 disabled:opacity-40"
            disabled={!hasUnsavedChanges || saving}
            onClick={() => void saveAll()}
          >
            {saving ? "Saving…" : "Save"}
          </button>
        </div>
      </div>

      <TradingRuleTemplatesField
        current={prefs}
        disabled={saving}
        onApply={(patch: TradingRuleTemplateSuggestion) => updateGlobal(patch)}
      />

      <section className="space-y-4 rounded-2xl border border-white/10 bg-white/5 p-5">
        <h3 className="text-sm font-semibold text-blue-100">Trading profile</h3>
        <Field
          label="Trading style"
          description="How you usually trade. Leave this unset if you do not want a style on file."
        >
          <div className="flex flex-wrap gap-2">
            {TRADING_STYLE_OPTIONS.map((option) => {
              const selected = prefs.tradingStyle === option.id
              return (
                <button
                  key={option.id}
                  type="button"
                  disabled={saving}
                  className={`rounded-xl border px-3 py-2 text-left text-sm ${
                    selected
                      ? "border-blue-400/70 bg-blue-500/15 text-white"
                      : "border-white/10 text-gray-200 hover:bg-white/10"
                  }`}
                  onClick={() => {
                    const next: TradingStyleId | null = selected ? null : option.id
                    updateGlobal({ tradingStyle: next })
                  }}
                >
                  <span className="block font-medium">{option.label}</span>
                  <span className="block text-xs text-gray-400">{option.description}</span>
                </button>
              )
            })}
          </div>
        </Field>

        <Field
          label="Preferred trading sessions"
          description="Sessions you plan to trade. None selected means this rule stays off."
        >
          <div className="flex flex-wrap gap-2">
            {TRADING_PREFERENCE_SESSIONS.map((session) => {
              const selected = prefs.preferredSessions.includes(session)
              return (
                <button
                  key={session}
                  type="button"
                  disabled={saving}
                  className={`rounded-full border px-3 py-1.5 text-sm ${
                    selected
                      ? "border-blue-400/70 bg-blue-500/15 text-white"
                      : "border-white/10 text-gray-200"
                  }`}
                  onClick={() => {
                    const next = selected
                      ? prefs.preferredSessions.filter((item) => item !== session)
                      : [...prefs.preferredSessions, session as TradingPreferenceSession]
                    updateGlobal({ preferredSessions: next })
                  }}
                >
                  {session}
                </button>
              )
            })}
          </div>
        </Field>

        <Field
          label="Primary trading instruments"
          description="Symbols you want analytics to recognize, such as ES or NQ. Leave this empty to skip it."
        >
          <div className="flex gap-2">
            <input
              className={inputClass}
              value={instrumentDraft}
              placeholder="Add a symbol"
              onChange={(event) => setInstrumentDraft(event.target.value)}
              onKeyDown={(event) => {
                if (event.key !== "Enter") return
                event.preventDefault()
                const symbol = instrumentDraft.trim().toUpperCase()
                if (!symbol) return
                if (!/^[A-Z0-9./-]{1,16}$/.test(symbol)) {
                  setError("Use 1–16 letters, numbers, or . / - for a symbol.")
                  return
                }
                if (prefs.primaryInstruments.includes(symbol)) {
                  setInstrumentDraft("")
                  return
                }
                updateGlobal({
                  primaryInstruments: [...prefs.primaryInstruments, symbol].slice(0, 12),
                })
                setInstrumentDraft("")
              }}
            />
            <button
              type="button"
              className={buttonClass}
              disabled={saving || !instrumentDraft.trim()}
              onClick={() => {
                const symbol = instrumentDraft.trim().toUpperCase()
                if (!/^[A-Z0-9./-]{1,16}$/.test(symbol)) {
                  setError("Use 1–16 letters, numbers, or . / - for a symbol.")
                  return
                }
                updateGlobal({
                  primaryInstruments: [...new Set([...prefs.primaryInstruments, symbol])].slice(
                    0,
                    12
                  ),
                })
                setInstrumentDraft("")
              }}
            >
              Add
            </button>
          </div>
          <div className="flex flex-wrap gap-2">
            {prefs.primaryInstruments.map((symbol) => (
              <button
                key={symbol}
                type="button"
                className={buttonClass}
                onClick={() =>
                  updateGlobal({
                    primaryInstruments: prefs.primaryInstruments.filter((item) => item !== symbol),
                  })
                }
              >
                {symbol} · Remove
              </button>
            ))}
          </div>
        </Field>
      </section>

      <section className="space-y-4 rounded-2xl border border-white/10 bg-white/5 p-5">
        <h3 className="text-sm font-semibold text-blue-100">Rules</h3>
        <NumberRule
          label="Target R:R"
          description="Your planned reward multiple. Example: 2 means 2R. Leave blank to leave target R off."
          unit="R"
          value={prefs.targetRr}
          disabled={saving}
          parse={(raw) => parseOptionalPositive(raw)}
          invalid="Enter a target above 0, or leave it blank."
          onSave={(value) => updateGlobal({ targetRr: value })}
        />
        <NumberRule
          label="Maximum trades per day"
          description="The daily count you want treated as your cap. Leave blank to leave this off."
          unit="trades"
          value={prefs.maxTradesPerDay}
          disabled={saving}
          parse={(raw) => parseOptionalInteger(raw, 1, 100)}
          invalid="Enter a whole number from 1 to 100, or leave it blank."
          onSave={(value) => updateGlobal({ maxTradesPerDay: value })}
        />
        {prefs.maxTradesPerDay != null ? (
          <TradingRuleScopeField
            value={prefs.maxTradesPerDayScope}
            disabled={saving}
            onChange={(scope) => updateGlobal({ maxTradesPerDayScope: scope })}
          />
        ) : null}
        <NumberRule
          label="Maximum risk per trade"
          description="Dollar risk at entry when your journal records it on a trade. TradeTraxs does not infer this from P&L."
          unit="USD"
          value={prefs.maxRiskPerTrade}
          disabled={saving}
          parse={(raw) => parseOptionalPositive(raw)}
          invalid="Enter a dollar amount above 0, or leave it blank."
          onSave={(value) => updateGlobal({ maxRiskPerTrade: value })}
        />
        <NumberRule
          label="Minimum acceptable R:R"
          description="Your floor for the planned (target) R:R saved on a trade — not realized or max R."
          unit="R"
          value={prefs.minAcceptableRr}
          disabled={saving}
          parse={(raw) => parseOptionalPositive(raw)}
          invalid="Enter a minimum R above 0, or leave it blank."
          onSave={(value) => updateGlobal({ minAcceptableRr: value })}
        />
        <NumberRule
          label="Maximum contracts per trade"
          description="Uses the contract size saved on each trade. Leave blank to leave this off."
          unit="contracts"
          value={prefs.maxContractsPerTrade}
          disabled={saving}
          parse={(raw) => parseOptionalInteger(raw, 1, 10000)}
          invalid="Enter a whole number from 1 to 10,000, or leave it blank."
          onSave={(value) => updateGlobal({ maxContractsPerTrade: value })}
        />
        <Field
          label="Allowed trading days"
          description="Eastern entry-day weekdays. None selected means this rule is off."
        >
          <div className="flex flex-wrap gap-2">
            {TRADING_RULE_WEEKDAYS.map((day) => {
              const selected = prefs.allowedTradingDays.includes(day)
              return (
                <button
                  key={day}
                  type="button"
                  className={buttonClass}
                  disabled={saving}
                  onClick={() => {
                    const next = selected
                      ? prefs.allowedTradingDays.filter((item) => item !== day)
                      : [...prefs.allowedTradingDays, day as TradingRuleWeekday]
                    updateGlobal({
                      allowedTradingDays: TRADING_RULE_WEEKDAYS.filter((d) =>
                        next.includes(d)
                      ) as TradingRuleWeekday[],
                    })
                  }}
                >
                  {weekdayDisplayLabel(day)}
                  {selected ? " · On" : ""}
                </button>
              )
            })}
          </div>
        </Field>
        <NumberRule
          label="Daily loss limit"
          description="The loss amount that counts as your daily limit. Stored as a positive dollar amount."
          unit="USD"
          value={prefs.dailyLossLimit}
          disabled={saving}
          parse={(raw) => parseOptionalPositive(raw)}
          invalid="Enter a dollar amount above 0, or leave it blank."
          onSave={(value) => updateGlobal({ dailyLossLimit: value })}
        />
        {prefs.dailyLossLimit != null ? (
          <TradingRuleScopeField
            value={prefs.dailyLossLimitScope}
            disabled={saving}
            onChange={(scope) => updateGlobal({ dailyLossLimitScope: scope })}
          />
        ) : null}
        <NumberRule
          label="Consecutive losses before a break"
          description="How many losses in a row you want flagged before a pause. Leave blank to leave this off."
          unit="losses"
          value={prefs.consecutiveLossPause}
          disabled={saving}
          parse={(raw) => parseOptionalInteger(raw, 1, 50)}
          invalid="Enter a whole number from 1 to 50, or leave it blank."
          onSave={(value) => updateGlobal({ consecutiveLossPause: value })}
        />
        <NumberRule
          label="Breakeven tolerance"
          description="Dollar distance from zero that still counts as breakeven. Blank keeps exact $0."
          unit="USD"
          value={prefs.breakevenTolerance}
          disabled={saving}
          parse={(raw) => parseOptionalNonNegative(raw)}
          invalid="Enter 0 or a dollar amount, or leave it blank for exact $0."
          onSave={(value) => updateGlobal({ breakevenTolerance: value })}
        />
      </section>

      <section className="space-y-4 rounded-2xl border border-white/10 bg-white/5 p-5">
        <h3 className="text-sm font-semibold text-blue-100">Advanced</h3>
        <NumberRule
          label="Daily profit target"
          description="A dollar goal for the day. Leave blank to leave the target off."
          unit="USD"
          value={prefs.dailyProfitTarget}
          disabled={saving}
          parse={(raw) => parseOptionalPositive(raw)}
          invalid="Enter a dollar amount above 0, or leave it blank."
          onSave={(value) =>
            updateGlobal({
              dailyProfitTarget: value,
              stopAfterDailyProfitTarget:
                value == null ? false : prefs.stopAfterDailyProfitTarget,
            })
          }
        />
        {prefs.dailyProfitTarget != null ? (
          <>
            <TradingRuleScopeField
              value={prefs.dailyProfitRulesScope}
              disabled={saving}
              onChange={(scope) => updateGlobal({ dailyProfitRulesScope: scope })}
            />
            <Field
              label="Stop trading after daily profit target"
              description="Flags trades entered after the day's profit tally reaches your target (not the trade that crosses it)."
            >
              <label className="flex items-center gap-2 text-sm text-gray-200">
                <input
                  type="checkbox"
                  disabled={saving}
                  checked={prefs.stopAfterDailyProfitTarget}
                  onChange={(event) =>
                    updateGlobal({ stopAfterDailyProfitTarget: event.target.checked })
                  }
                />
                Enable stop-after-target rule
              </label>
            </Field>
          </>
        ) : null}
        <NumberRule
          label="Maximum weekly loss"
          description="Weekly loss total in Eastern time, evaluated in trade order. Leave blank to leave this off."
          unit="USD"
          value={prefs.maxWeeklyLoss}
          disabled={saving}
          parse={(raw) => parseOptionalPositive(raw)}
          invalid="Enter a dollar amount above 0, or leave it blank."
          onSave={(value) => updateGlobal({ maxWeeklyLoss: value })}
        />
        {prefs.maxWeeklyLoss != null ? (
          <TradingRuleScopeField
            value={prefs.maxWeeklyLossScope}
            disabled={saving}
            onChange={(scope) => updateGlobal({ maxWeeklyLossScope: scope })}
          />
        ) : null}
        <NumberRule
          label="Maximum drawdown goal"
          description="Your personal drawdown goal in dollars. This is separate from a prop account’s max loss."
          unit="USD"
          value={prefs.maxDrawdownGoal}
          disabled={saving}
          parse={(raw) => parseOptionalPositive(raw)}
          invalid="Enter a dollar amount above 0, or leave it blank."
          onSave={(value) => updateGlobal({ maxDrawdownGoal: value })}
        />
        <Field
          label="Planned trading hours"
          description={
            prefs.plannedStartMinute != null && prefs.plannedEndMinute != null
              ? `Eastern time. Current window: ${formatMinuteLabel(prefs.plannedStartMinute)} to ${formatMinuteLabel(prefs.plannedEndMinute)}. The window can cross midnight.`
              : "Eastern time. Set both a start and an end, or leave both blank. The window can cross midnight."
          }
        >
          <div className="flex flex-wrap items-center gap-2">
            <input
              type="time"
              className={inputClass}
              style={{ maxWidth: 160 }}
              value={minutesToTimeInput(prefs.plannedStartMinute)}
              onChange={(event) => {
                const start = timeInputToMinutes(event.target.value)
                if (start === "invalid") return
                const end = prefs.plannedEndMinute
                if (start != null && end != null && start === end) {
                  setError("Start and end need to be different times.")
                  return
                }
                if ((start == null) !== (end == null) && event.target.value && end == null) {
                  updateGlobal({ plannedStartMinute: start })
                  return
                }
                updateGlobal({
                  plannedStartMinute: start,
                  plannedEndMinute: start == null ? null : end,
                })
              }}
            />
            <span className="text-sm text-gray-400">to</span>
            <input
              type="time"
              className={inputClass}
              style={{ maxWidth: 160 }}
              value={minutesToTimeInput(prefs.plannedEndMinute)}
              onChange={(event) => {
                const end = timeInputToMinutes(event.target.value)
                if (end === "invalid") return
                const start = prefs.plannedStartMinute
                if (start != null && end != null && start === end) {
                  setError("Start and end need to be different times.")
                  return
                }
                updateGlobal({
                  plannedStartMinute: end == null ? null : start,
                  plannedEndMinute: end,
                })
              }}
            />
            <button
              type="button"
              className={buttonClass}
              disabled={saving || (prefs.plannedStartMinute == null && prefs.plannedEndMinute == null)}
              onClick={() =>
                updateGlobal({ plannedStartMinute: null, plannedEndMinute: null })
              }
            >
              Reset
            </button>
          </div>
        </Field>
        <NumberRule
          label="Waiting time after a loss"
          description="Minutes you want to wait after a losing trade. Leave blank to leave this off."
          unit="minutes"
          value={prefs.waitAfterLossMinutes}
          disabled={saving}
          parse={(raw) => parseOptionalInteger(raw, 0, 1440)}
          invalid="Enter whole minutes from 0 to 1440, or leave it blank."
          onSave={(value) => updateGlobal({ waitAfterLossMinutes: value })}
        />
      </section>

      <section className="space-y-4 rounded-2xl border border-white/10 bg-white/5 p-5">
        <h3 className="text-sm font-semibold text-blue-100">Account dollar limits</h3>
        <p className="text-xs leading-5 text-gray-400">
          Optional. A custom amount replaces the global dollar limit for that account.
          Turning a custom limit off uses the global amount again. Style, sessions, and the other rules stay global.
        </p>
        {accounts.length === 0 || !selectedOverride ? (
          <p className="text-sm text-gray-400">Add a trading account to set an account limit.</p>
        ) : (
          <>
            <select
              className={inputClass}
              value={accountId}
              onChange={(event) => setAccountId(event.target.value)}
            >
              {accounts.map((account) => (
                <option key={account.id} value={account.id}>
                  {account.name}
                </option>
              ))}
            </select>
            <OverrideRule
              label="Daily loss limit"
              unit="USD"
              enabled={selectedOverride.overridesDailyLoss}
              value={selectedOverride.dailyLossLimit}
              disabled={saving}
              onDraftChange={(enabled, value) =>
                updateDraftOverride({
                  ...selectedOverride,
                  overridesDailyLoss: enabled,
                  dailyLossLimit: enabled ? value : null,
                })
              }
            />
            <OverrideRule
              label="Daily profit target"
              unit="USD"
              enabled={selectedOverride.overridesDailyProfitTarget}
              value={selectedOverride.dailyProfitTarget}
              disabled={saving}
              onDraftChange={(enabled, value) =>
                updateDraftOverride({
                  ...selectedOverride,
                  overridesDailyProfitTarget: enabled,
                  dailyProfitTarget: enabled ? value : null,
                })
              }
            />
            <OverrideRule
              label="Maximum drawdown goal"
              unit="USD"
              enabled={selectedOverride.overridesMaxDrawdownGoal}
              value={selectedOverride.maxDrawdownGoal}
              disabled={saving}
              onDraftChange={(enabled, value) =>
                updateDraftOverride({
                  ...selectedOverride,
                  overridesMaxDrawdownGoal: enabled,
                  maxDrawdownGoal: enabled ? value : null,
                })
              }
            />
          </>
        )}
      </section>
    </div>
  )
}

function NumberRule({
  label,
  description,
  unit,
  value,
  disabled,
  parse,
  invalid,
  onSave,
}: {
  label: string
  description: string
  unit: string
  value: number | null
  disabled: boolean
  parse: (raw: string) => number | null | "invalid"
  invalid: string
  onSave: (value: number | null) => void
}) {
  const [draft, setDraft] = useState(value == null ? "" : String(value))
  const [localError, setLocalError] = useState<string | null>(null)

  useEffect(() => {
    setDraft(value == null ? "" : String(value))
  }, [value])

  return (
    <Field label={label} description={description}>
      <div className="flex flex-wrap items-center gap-2">
        <input
          className={inputClass}
          style={{ maxWidth: 180 }}
          inputMode="decimal"
          value={draft}
          disabled={disabled}
          onChange={(event) => setDraft(event.target.value)}
          onBlur={() => {
            const parsed = parse(draft)
            if (parsed === "invalid") {
              if (draft.trim() !== "") setLocalError(invalid)
              return
            }
            setLocalError(null)
            if (parsed !== value) onSave(parsed)
          }}
        />
        <span className="text-xs text-gray-400">{unit}</span>
        <button
          type="button"
          className={buttonClass}
          disabled={disabled || value == null}
          onClick={() => {
            setDraft("")
            setLocalError(null)
            onSave(null)
          }}
        >
          Reset
        </button>
      </div>
      {localError ? <span className="block text-xs text-red-300">{localError}</span> : null}
    </Field>
  )
}

function OverrideRule({
  label,
  unit,
  enabled,
  value,
  disabled,
  onDraftChange,
}: {
  label: string
  unit: string
  enabled: boolean
  value: number | null
  disabled: boolean
  onDraftChange: (enabled: boolean, value: number | null) => void
}) {
  const [draft, setDraft] = useState(value == null ? "" : String(value))
  const [localError, setLocalError] = useState<string | null>(null)

  useEffect(() => {
    setDraft(value == null ? "" : String(value))
  }, [value])

  return (
    <Field
      label={label}
      description={
        enabled
          ? value == null
            ? "Custom rule is on with no amount, so this limit is off for the account."
            : `Custom amount in ${unit}. Reset returns to the global limit.`
          : "Using the global limit."
      }
    >
      <div className="flex flex-wrap items-center gap-2">
        <input
          className={inputClass}
          style={{ maxWidth: 180 }}
          inputMode="decimal"
          value={draft}
          disabled={disabled}
          onChange={(event) => setDraft(event.target.value)}
          onBlur={() => {
            const parsed = parseOptionalPositive(draft)
            if (parsed === "invalid") {
              if (draft.trim() !== "") setLocalError("Enter a dollar amount above 0.")
              return
            }
            setLocalError(null)
            const nextEnabled = parsed != null
            if (nextEnabled !== enabled || parsed !== value) {
              onDraftChange(nextEnabled, parsed)
            }
          }}
        />
        <span className="text-xs text-gray-400">{unit}</span>
        <button
          type="button"
          className={buttonClass}
          disabled={disabled}
          onClick={() => {
            const parsed = parseOptionalPositive(draft)
            if (parsed === "invalid") {
              setLocalError("Enter a dollar amount above 0.")
              return
            }
            setLocalError(null)
            onDraftChange(parsed != null, parsed)
          }}
        >
          Use custom amount
        </button>
        <button
          type="button"
          className={buttonClass}
          disabled={disabled || !enabled}
          onClick={() => {
            setDraft("")
            setLocalError(null)
            onDraftChange(false, null)
          }}
        >
          Reset
        </button>
      </div>
      {localError ? <span className="block text-xs text-red-300">{localError}</span> : null}
    </Field>
  )
}
