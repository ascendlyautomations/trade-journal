"use client"

import { useEffect, useMemo, useState } from "react"
import Modal from "@/app/components/ui/Modal"
import {
  formatPropfirmUsd,
  type PayoutDrawdownBehavior,
} from "@/lib/propfirmMetrics"

export type PayoutSetupValues = {
  balanceAfterPayout: number
  payoutAmount: number
  drawdownBehavior: PayoutDrawdownBehavior
  rememberDrawdownBehavior: boolean
}

export type PayoutSetupModalProps = {
  open: boolean
  onClose: () => void
  onSubmit: (values: PayoutSetupValues) => void | Promise<void>
  busy?: boolean
  accountBaseBalance: number
  balanceBeforePayout: number
  defaultDrawdownBehavior: PayoutDrawdownBehavior
  defaultRememberDrawdownBehavior?: boolean
}

const INPUT_CLASS =
  "mt-1.5 h-10 w-full rounded-lg border border-white/10 bg-black/30 px-3 text-sm text-white outline-none transition focus:border-blue-500/40 focus:ring-2 focus:ring-blue-500/20"

function parseCurrencyInput(value: string): number | null {
  const trimmed = value.replace(/,/g, "").trim()
  if (!trimmed) return null
  const parsed = Number(trimmed)
  if (!Number.isFinite(parsed) || parsed < 0) return null
  return parsed
}

export default function PayoutSetupModal({
  open,
  onClose,
  onSubmit,
  busy = false,
  accountBaseBalance,
  balanceBeforePayout,
  defaultDrawdownBehavior,
  defaultRememberDrawdownBehavior = false,
}: PayoutSetupModalProps) {
  const [balanceAfterDraft, setBalanceAfterDraft] = useState("")
  const [payoutAmountDraft, setPayoutAmountDraft] = useState("")
  const [drawdownBehavior, setDrawdownBehavior] =
    useState<PayoutDrawdownBehavior>(defaultDrawdownBehavior)
  const [rememberBehavior, setRememberBehavior] = useState(
    defaultRememberDrawdownBehavior
  )

  useEffect(() => {
    if (!open) return
    setBalanceAfterDraft(String(Math.round(balanceBeforePayout)))
    setPayoutAmountDraft("")
    setDrawdownBehavior(defaultDrawdownBehavior)
    setRememberBehavior(defaultRememberDrawdownBehavior)
  }, [
    open,
    balanceBeforePayout,
    defaultDrawdownBehavior,
    defaultRememberDrawdownBehavior,
  ])

  const balanceAfter = parseCurrencyInput(balanceAfterDraft)
  const payoutAmount = parseCurrencyInput(payoutAmountDraft)

  useEffect(() => {
    if (!open || payoutAmount == null || payoutAmount <= 0) return
    const suggested = Math.max(0, balanceBeforePayout - payoutAmount)
    setBalanceAfterDraft(String(Math.round(suggested * 100) / 100))
  }, [open, payoutAmountDraft, balanceBeforePayout])

  const canSubmit =
    balanceAfter != null &&
    payoutAmount != null &&
    payoutAmount > 0 &&
    !busy

  const resetExample = useMemo(() => {
    const growth = balanceBeforePayout
    const withdraw = payoutAmount ?? 1250
    const after = balanceAfter ?? growth - withdraw
    return {
      growth,
      withdraw,
      after,
      floor: accountBaseBalance,
    }
  }, [accountBaseBalance, balanceAfter, balanceBeforePayout, payoutAmount])

  const trailingExample = useMemo(() => {
    const growth = balanceBeforePayout
    const withdraw = payoutAmount ?? 1250
    const after = balanceAfter ?? growth - withdraw
    const floor = Math.max(0, growth - 1000)
    return { growth, withdraw, after, floor }
  }, [balanceAfter, balanceBeforePayout, payoutAmount])

  return (
    <Modal
      open={open}
      onClose={() => {
        if (!busy) onClose()
      }}
      title="Payout Setup"
      size="lg"
      footer={
        <div className="flex justify-end gap-3">
          <button
            type="button"
            disabled={busy}
            onClick={onClose}
            className="rounded-lg border border-white/10 bg-white/5 px-4 py-2 text-sm font-medium text-gray-200 transition hover:bg-white/10 disabled:cursor-not-allowed disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            disabled={!canSubmit}
            onClick={() => {
              if (!canSubmit || balanceAfter == null || payoutAmount == null) return
              void onSubmit({
                balanceAfterPayout: balanceAfter,
                payoutAmount,
                drawdownBehavior,
                rememberDrawdownBehavior: rememberBehavior,
              })
            }}
            className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-500 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {busy ? "Recording…" : "Record Payout"}
          </button>
        </div>
      }
    >
      <p className="text-sm leading-relaxed text-gray-300">
        Set your account balance and drawdown rules after this payout. Lifetime
        trades and statistics stay unchanged — only the current payout cycle
        resets.
      </p>

      <label className="mt-5 block text-xs text-gray-300">
        What is your current account balance after receiving your payout?
        <input
          type="number"
          min="0"
          step="0.01"
          value={balanceAfterDraft}
          onChange={(e) => setBalanceAfterDraft(e.target.value)}
          placeholder="50250"
          className={INPUT_CLASS}
        />
        {balanceAfter != null ? (
          <span className="mt-1 block text-xs text-gray-500">
            New current balance: {formatPropfirmUsd(balanceAfter)}
          </span>
        ) : null}
      </label>

      <label className="mt-4 block text-xs text-gray-300">
        How much was your payout?
        <input
          type="number"
          min="0"
          step="0.01"
          value={payoutAmountDraft}
          onChange={(e) => setPayoutAmountDraft(e.target.value)}
          placeholder="1250"
          className={INPUT_CLASS}
        />
      </label>

      <fieldset className="mt-5">
        <legend className="text-xs font-medium text-gray-300">
          How does your prop firm handle drawdown after a payout?
        </legend>
        <div className="mt-3 space-y-3">
          <label
            className={`block cursor-pointer rounded-lg border px-3 py-3 transition ${
              drawdownBehavior === "reset_to_account"
                ? "border-blue-500/40 bg-blue-500/10"
                : "border-white/10 bg-white/5 hover:bg-white/[0.07]"
            }`}
          >
            <div className="flex items-start gap-2.5">
              <input
                type="radio"
                name="drawdown-behavior"
                checked={drawdownBehavior === "reset_to_account"}
                onChange={() => setDrawdownBehavior("reset_to_account")}
                className="mt-0.5"
              />
              <div>
                <p className="text-sm font-medium text-gray-100">
                  Reset drawdown to account value
                </p>
                <p className="mt-1 text-xs leading-relaxed text-gray-400">
                  Starting account: {formatPropfirmUsd(accountBaseBalance)} →
                  grows to {formatPropfirmUsd(resetExample.growth)} → withdraw{" "}
                  {formatPropfirmUsd(resetExample.withdraw)} → current balance{" "}
                  {formatPropfirmUsd(resetExample.after)}. Lowest allowed
                  balance becomes {formatPropfirmUsd(resetExample.floor)}.
                </p>
              </div>
            </div>
          </label>

          <label
            className={`block cursor-pointer rounded-lg border px-3 py-3 transition ${
              drawdownBehavior === "keep_trailing"
                ? "border-blue-500/40 bg-blue-500/10"
                : "border-white/10 bg-white/5 hover:bg-white/[0.07]"
            }`}
          >
            <div className="flex items-start gap-2.5">
              <input
                type="radio"
                name="drawdown-behavior"
                checked={drawdownBehavior === "keep_trailing"}
                onChange={() => setDrawdownBehavior("keep_trailing")}
                className="mt-0.5"
              />
              <div>
                <p className="text-sm font-medium text-gray-100">
                  Keep trailing drawdown
                </p>
                <p className="mt-1 text-xs leading-relaxed text-gray-400">
                  Same growth and withdrawal — current balance{" "}
                  {formatPropfirmUsd(trailingExample.after)}. Drawdown floor
                  stays at the previous trailing level (e.g.{" "}
                  {formatPropfirmUsd(trailingExample.floor)}).
                </p>
              </div>
            </div>
          </label>
        </div>
      </fieldset>

      <label className="mt-4 flex cursor-pointer items-center gap-2 text-sm text-gray-300">
        <input
          type="checkbox"
          checked={rememberBehavior}
          onChange={(e) => setRememberBehavior(e.target.checked)}
          className="rounded border-white/20"
        />
        Remember this drawdown behavior for this account
      </label>
    </Modal>
  )
}
