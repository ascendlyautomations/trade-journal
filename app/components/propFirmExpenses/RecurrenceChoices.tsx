"use client"

import { EXPENSE_RECURRENCES, type ExpenseRecurrence } from "@/lib/expenseRecurrence"
import { READABLE_FIELD_LABEL_CLASS } from "@/lib/readableTextStyles"

export default function RecurrenceChoices({
  value,
  onChange,
}: {
  value: ExpenseRecurrence | ""
  onChange: (value: ExpenseRecurrence | "") => void
}) {
  return (
    <div>
      <span className={READABLE_FIELD_LABEL_CLASS}>Recurring</span>
      <div className="mt-2 flex flex-wrap gap-2">
        {EXPENSE_RECURRENCES.map((item) => {
          const selected = value === item.value
          return (
            <button
              key={item.value}
              type="button"
              aria-pressed={selected}
              onClick={() => onChange(selected ? "" : item.value)}
              className={`rounded-full border px-3 py-1 text-sm ${
                selected
                  ? "border-transparent bg-blue-500 text-white"
                  : "border-white/15 bg-white/10 text-gray-100"
              }`}
            >
              {item.label}
            </button>
          )
        })}
      </div>
      <p className="mt-2 text-xs text-gray-400">
        {value
          ? "Every date from the start through today is included. A future date is added when that day arrives."
          : "Leave these off for a one-time amount."}
      </p>
    </div>
  )
}
