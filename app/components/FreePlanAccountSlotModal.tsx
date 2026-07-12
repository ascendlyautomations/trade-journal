"use client"

import { useEffect, useMemo, useState } from "react"
import Modal from "@/app/components/ui/Modal"
import ConfirmModal from "@/app/components/ui/ConfirmModal"
import { buttonVariants, cn } from "@/app/components/ui"
import {
  FREE_PLAN_ACCOUNT_LIMIT,
  formatTradingAccountMode,
} from "@/lib/tradingAccounts"
import { formatSignedPnlDisplay } from "@/lib/formatDisplay"
import { formatAccountNameWithSizeDisplay } from "@/lib/tradeAccountDisplay"

export type FreePlanSlotAccountOption = {
  id: string
  name: string
  size: string
  mode: string | null
  category: string | null
  tradeCount: number
  lifetimePnl: number
  lastTradeDate: string | null
}

type FreePlanAccountSlotModalProps = {
  open: boolean
  accounts: FreePlanSlotAccountOption[]
  saving?: boolean
  error?: string | null
  onConfirm: (accountIds: string[]) => void | Promise<void>
}

const ZERO_SELECTION_CONFIRM_MESSAGE =
  "You haven't selected any active accounts. You'll still have access to all historical data, but you won't be able to add new trades until you activate or create an account. Continue?"

function formatBrokerLabel(category: string | null): string {
  const raw = String(category ?? "").trim()
  if (!raw) return "—"
  if (raw.toLowerCase() === "prop firm") return "Prop Firm"
  if (raw.toLowerCase() === "personal") return "Personal"
  if (raw.toLowerCase() === "broker") return "Broker"
  return raw
}

function formatLastTradeDate(value: string | null): string {
  if (!value) return "—"
  const d = new Date(value)
  if (Number.isNaN(d.getTime())) return "—"
  return d.toLocaleDateString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
  })
}

export default function FreePlanAccountSlotModal({
  open,
  accounts,
  saving = false,
  error = null,
  onConfirm,
}: FreePlanAccountSlotModalProps) {
  const [selectedIds, setSelectedIds] = useState<string[]>([])
  const [confirmZeroOpen, setConfirmZeroOpen] = useState(false)

  const sortedAccounts = useMemo(
    () =>
      [...accounts].sort((a, b) => {
        const aDate = a.lastTradeDate ? Date.parse(a.lastTradeDate) : 0
        const bDate = b.lastTradeDate ? Date.parse(b.lastTradeDate) : 0
        if (aDate !== bDate) return bDate - aDate
        return a.name.localeCompare(b.name)
      }),
    [accounts]
  )

  const accountKey = accounts.map((a) => a.id).join(",")

  useEffect(() => {
    if (!open) {
      setSelectedIds([])
      setConfirmZeroOpen(false)
      return
    }
    setSelectedIds([])
    setConfirmZeroOpen(false)
  }, [open, accountKey])

  function toggleAccount(id: string) {
    setSelectedIds((prev) => {
      if (prev.includes(id)) return prev.filter((x) => x !== id)
      if (prev.length >= FREE_PLAN_ACCOUNT_LIMIT) return prev
      return [...prev, id]
    })
  }

  function handleKeepSelectedClick() {
    if (saving) return
    if (selectedIds.length === 0) {
      setConfirmZeroOpen(true)
      return
    }
    void onConfirm(selectedIds)
  }

  async function handleConfirmZero() {
    setConfirmZeroOpen(false)
    await onConfirm([])
  }

  return (
    <>
      <Modal
        open={open}
        onClose={() => {}}
        closeDisabled
        showCloseButton={false}
        size="lg"
        title="Your Pro access has ended"
        footer={
          <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
            <p className="text-xs text-gray-400">
              Selected {selectedIds.length} of {FREE_PLAN_ACCOUNT_LIMIT} max
            </p>
            <button
              type="button"
              disabled={saving}
              onClick={handleKeepSelectedClick}
              className={cn(
                buttonVariants({ variant: "primary", size: "md" }),
                "w-full justify-center sm:w-auto"
              )}
            >
              {saving ? "Saving…" : "Keep Selected Accounts"}
            </button>
          </div>
        }
      >
        <div className="space-y-4">
          <div className="space-y-2 text-sm leading-relaxed text-gray-300">
            <p>
              The Free plan supports up to {FREE_PLAN_ACCOUNT_LIMIT} active
              trading accounts.
            </p>
            <p>
              Choose which accounts you&apos;d like to keep active. You can keep
              anywhere from 0 to {FREE_PLAN_ACCOUNT_LIMIT} accounts. Any accounts
              you don&apos;t keep will remain available in read-only mode with
              all trade history preserved.
            </p>
          </div>

          {error ? (
            <p className="rounded-lg border border-red-500/30 bg-red-500/10 px-3 py-2 text-sm text-red-200">
              {error}
            </p>
          ) : null}

          <ul className="max-h-[min(50dvh,420px)] space-y-2 overflow-y-auto overscroll-contain pr-1">
            {sortedAccounts.map((account) => {
              const checked = selectedIds.includes(account.id)
              const disabled =
                !checked && selectedIds.length >= FREE_PLAN_ACCOUNT_LIMIT
              const title = formatAccountNameWithSizeDisplay(
                account.name,
                account.size
              )
              const typeLabel = formatTradingAccountMode(account.mode) ?? "—"
              const brokerLabel = formatBrokerLabel(account.category)
              const pnlPositive = account.lifetimePnl > 0
              const pnlNegative = account.lifetimePnl < 0

              return (
                <li key={account.id}>
                  <label
                    className={cn(
                      "flex cursor-pointer items-start gap-3 rounded-xl border p-3 transition",
                      checked
                        ? "border-blue-400/40 bg-blue-500/10"
                        : "border-white/10 bg-white/[0.03] hover:bg-white/[0.06]",
                      disabled ? "cursor-not-allowed opacity-50" : null
                    )}
                  >
                    <input
                      type="checkbox"
                      className="mt-1"
                      checked={checked}
                      disabled={disabled || saving}
                      onChange={() => toggleAccount(account.id)}
                    />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-sm font-medium text-white">
                        {title || account.name || "—"}
                      </span>
                      <span className="mt-1 block text-xs text-gray-400">
                        {typeLabel} · {brokerLabel}
                      </span>
                      <span className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-gray-300">
                        <span>
                          Trades:{" "}
                          <span className="tabular-nums text-gray-100">
                            {account.tradeCount.toLocaleString()}
                          </span>
                        </span>
                        <span>
                          Lifetime P&L:{" "}
                          <span
                            className={cn(
                              "tabular-nums",
                              pnlPositive
                                ? "text-emerald-300"
                                : pnlNegative
                                  ? "text-red-300"
                                  : "text-gray-100"
                            )}
                          >
                            {formatSignedPnlDisplay(account.lifetimePnl)}
                          </span>
                        </span>
                        <span>
                          Last trade:{" "}
                          <span className="text-gray-100">
                            {formatLastTradeDate(account.lastTradeDate)}
                          </span>
                        </span>
                      </span>
                    </span>
                  </label>
                </li>
              )
            })}
          </ul>
        </div>
      </Modal>

      <ConfirmModal
        open={confirmZeroOpen}
        title="Continue?"
        description={ZERO_SELECTION_CONFIRM_MESSAGE}
        confirmLabel="Continue"
        cancelLabel="Cancel"
        loading={saving}
        onCancel={() => setConfirmZeroOpen(false)}
        onConfirm={handleConfirmZero}
      />
    </>
  )
}
