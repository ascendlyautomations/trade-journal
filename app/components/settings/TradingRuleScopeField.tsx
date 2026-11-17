"use client"

import {
  TRADING_RULE_SCOPE_OPTIONS,
  type TradingRuleScope,
} from "@/lib/analytics/tradingPreferences"

type Props = {
  label?: string
  description?: string
  value: TradingRuleScope
  disabled?: boolean
  onChange: (value: TradingRuleScope) => void
}

export default function TradingRuleScopeField({
  label = "Applies To",
  description = "All Accounts Combined adds trades across accounts before checking the rule. Per Account checks each account on its own.",
  value,
  disabled,
  onChange,
}: Props) {
  return (
    <label className="block space-y-2">
      <span className="block text-xs font-medium text-gray-300">{label}</span>
      {description ? (
        <span className="block text-xs leading-5 text-gray-500">{description}</span>
      ) : null}
      <select
        className="w-full rounded-xl border border-white/10 bg-black/20 px-3 py-2 text-sm text-white outline-none focus:border-blue-400/60 disabled:opacity-40"
        disabled={disabled}
        value={value}
        onChange={(event) => onChange(event.target.value as TradingRuleScope)}
      >
        {TRADING_RULE_SCOPE_OPTIONS.map((option) => (
          <option key={option.id} value={option.id}>
            {option.label}
          </option>
        ))}
      </select>
    </label>
  )
}
