"use client"

import { useMemo, useState } from "react"
import {
  TRADING_RULE_TEMPLATES,
  type TradingRuleTemplateId,
  type TradingRuleTemplateSuggestion,
} from "@/lib/analytics/tradingRuleTemplates"
import type { TradingPreferenceGlobal } from "@/lib/analytics/tradingPreferences"

type Props = {
  current: TradingPreferenceGlobal
  onApply: (patch: TradingRuleTemplateSuggestion) => void
  disabled?: boolean
}

const selectClass =
  "w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm text-white outline-none focus:border-blue-400/60"

function summarizeValues(values: TradingRuleTemplateSuggestion): string[] {
  const lines: string[] = []
  if (values.preferredSessions?.length) {
    lines.push(`Sessions: ${values.preferredSessions.join(", ")}`)
  }
  if (values.maxTradesPerDay != null) {
    lines.push(`Daily trade cap: ${values.maxTradesPerDay}`)
  }
  if (values.dailyLossLimit != null) {
    lines.push(`Daily loss limit: $${values.dailyLossLimit}`)
  }
  if (values.dailyProfitTarget != null) {
    lines.push(
      `Daily profit target: $${values.dailyProfitTarget}${
        values.stopAfterDailyProfitTarget ? " (stop after)" : ""
      }`
    )
  }
  if (values.maxWeeklyLoss != null) {
    lines.push(`Weekly loss limit: $${values.maxWeeklyLoss}`)
  }
  if (values.maxRiskPerTrade != null) {
    lines.push(`Max risk / trade: $${values.maxRiskPerTrade}`)
  }
  if (values.minAcceptableRr != null) {
    lines.push(`Min planned R:R: ${values.minAcceptableRr}`)
  }
  if (values.allowedTradingDays?.length) {
    lines.push(`Allowed days: ${values.allowedTradingDays.length} weekdays`)
  }
  return lines
}

export default function TradingRuleTemplatesField({
  current,
  onApply,
  disabled,
}: Props) {
  const [pendingId, setPendingId] = useState<TradingRuleTemplateId | null>(null)
  const pending = useMemo(
    () =>
      pendingId
        ? TRADING_RULE_TEMPLATES.find((row) => row.id === pendingId) ?? null
        : null,
    [pendingId]
  )

  return (
    <div className="space-y-3 rounded-xl border border-white/10 bg-white/5 p-4">
      <div>
        <p className="text-sm font-semibold text-white">Rule templates</p>
        <p className="mt-1 text-xs text-gray-400">
          Prefill suggested values on this form only. Nothing saves until you tap
          Save. Applying a template replaces matching fields in your draft — confirm
          before continuing.
        </p>
      </div>
      <label className="block">
        <span className="sr-only">Rule template</span>
        <select
          className={selectClass}
          disabled={disabled}
          value={pendingId ?? ""}
          onChange={(event) => {
            const id = event.target.value as TradingRuleTemplateId | ""
            if (!id || id === "custom") {
              setPendingId(null)
              return
            }
            setPendingId(id)
          }}
        >
          <option value="">Choose a template…</option>
          {TRADING_RULE_TEMPLATES.filter((row) => row.id !== "custom").map(
            (template) => (
              <option key={template.id} value={template.id}>
                {template.label}
              </option>
            )
          )}
        </select>
      </label>

      {pending ? (
        <div className="space-y-3 rounded-lg border border-amber-400/30 bg-amber-400/5 p-3">
          <p className="text-sm font-semibold text-amber-100">{pending.label}</p>
          <p className="text-xs text-gray-300">{pending.description}</p>
          {pending.id === "custom" ? null : (
            <ul className="list-inside list-disc text-xs text-gray-400">
              {summarizeValues(pending.values).map((line) => (
                <li key={line}>{line}</li>
              ))}
            </ul>
          )}
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              className="rounded-lg bg-blue-500/20 px-3 py-1.5 text-xs font-semibold text-white hover:bg-blue-500/30"
              onClick={() => {
                onApply({ ...pending.values })
                setPendingId(null)
              }}
            >
              Apply to draft
            </button>
            <button
              type="button"
              className="rounded-lg border border-white/10 px-3 py-1.5 text-xs text-gray-300"
              onClick={() => setPendingId(null)}
            >
              Cancel
            </button>
          </div>
          <p className="text-[10px] text-gray-500">
            Current saved rules remain on the server until you save. Review every
            field before saving{current.tradingStyle ? ` (style: ${current.tradingStyle})` : ""}.
          </p>
        </div>
      ) : null}
    </div>
  )
}
