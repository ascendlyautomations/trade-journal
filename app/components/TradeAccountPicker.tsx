"use client"

import { useEffect, useState } from "react"

/** Mirrors `InputTradeForm` account row shape after `accounts` fetch. */
export type TradeAccountOption = {
  name: string
  size: string
  id: string
  account_number?: string | null
  mode: string | null
  category?: string | null
}

function accountNumberLabel(acc: {
  account_number?: string | null
  id?: string | null
}): string {
  const num = String(acc.account_number ?? "").trim()
  if (num) return num
  const id = String(acc.id ?? "").trim()
  if (!id) return "—"
  return id.length > 14 ? `${id.slice(0, 8)}…` : id
}

function formatAccountSize(size: unknown) {
  if (!size) return ""
  const num = Number(size)
  if (!Number.isNaN(num) && num >= 1000) {
    return `${num / 1000}K`
  }
  return String(size)
}

function formatMode(mode: unknown) {
  if (!mode) return "Live"
  const m = String(mode).toLowerCase()
  if (m === "eval") return "Eval"
  if (m === "funded") return "Funded"
  if (m === "live") return "Live"
  return String(mode)
}

type Props = {
  accounts: TradeAccountOption[]
  selectedAccount: TradeAccountOption | null
  onSelect: (acc: TradeAccountOption) => void
  onOpenCreate: () => void
  disableCreate?: boolean
}

/**
 * Same dropdown pattern as `InputTradeForm` (single desktop-width row).
 */
export default function TradeAccountPicker({
  accounts,
  selectedAccount,
  onSelect,
  onOpenCreate,
  disableCreate = false,
}: Props) {
  const [open, setOpen] = useState(false)

  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      const target = e.target as HTMLElement
      if (!target.closest(".trade-account-picker")) {
        setOpen(false)
      }
    }
    document.addEventListener("mousedown", handleClickOutside)
    return () => document.removeEventListener("mousedown", handleClickOutside)
  }, [])

  return (
    <div className="flex min-w-0 flex-col gap-2 sm:flex-row sm:items-stretch">
      <div className="relative min-w-0 flex-1 trade-account-picker">
        <button
          type="button"
          onClick={() => setOpen(!open)}
          className="flex w-full cursor-pointer items-center justify-between rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-left text-sm text-white"
        >
          <span className="truncate">
            {selectedAccount
              ? `${selectedAccount.name} • ${selectedAccount.size} • ${selectedAccount.category || "Personal"} • ${formatMode(selectedAccount.mode)} • #${accountNumberLabel(selectedAccount)}`
              : "Select Account"}
          </span>
          <span className="shrink-0 text-gray-400">▾</span>
        </button>
        {open ? (
          <div className="absolute z-[110] mt-1 max-h-60 w-full overflow-y-auto rounded-lg border border-white/10 bg-[#0f172a] shadow-lg">
            {accounts.map((acc) => (
              <div
                key={String(acc.id)}
                role="button"
                tabIndex={0}
                onClick={() => {
                  onSelect(acc)
                  setOpen(false)
                }}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault()
                    onSelect(acc)
                    setOpen(false)
                  }
                }}
                className="cursor-pointer px-3 py-2 text-sm text-white hover:bg-[#1f2937]"
              >
                {acc.name} • {formatAccountSize(acc.size)} • {acc.category || "Personal"} •{" "}
                {formatMode(acc.mode)} • #{accountNumberLabel(acc)}
              </div>
            ))}
            {!disableCreate ? (
              <div
                role="button"
                tabIndex={0}
                onClick={() => {
                  onOpenCreate()
                  setOpen(false)
                }}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault()
                    onOpenCreate()
                    setOpen(false)
                  }
                }}
                className="cursor-pointer px-3 py-2 text-sm text-green-400 hover:bg-[#1f2937]"
              >
                + Create New Account
              </div>
            ) : (
              <div className="px-3 py-2 text-sm text-amber-300/90">
                Upgrade to Pro to add more accounts
              </div>
            )}
          </div>
        ) : null}
      </div>
      <button
        type="button"
        onClick={onOpenCreate}
        disabled={disableCreate}
        className="shrink-0 rounded-lg border border-emerald-500/40 bg-emerald-500/15 px-4 py-2.5 text-sm font-medium text-emerald-200 transition hover:bg-emerald-500/25 disabled:cursor-not-allowed whitespace-normal text-center sm:whitespace-nowrap"
      >
        {disableCreate ? "Upgrade to Pro to add more accounts" : "+ Create Account"}
      </button>
    </div>
  )
}
