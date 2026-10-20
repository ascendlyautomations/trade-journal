"use client"

import Link from "next/link"
import {
  isLiveWithdrawalHistoryItem,
  isPropPayoutHistoryItem,
  payoutHistoryItemHref,
  type PayoutHistoryItem,
} from "@/lib/payoutHistory"
import {
  formatTradingAccountModeLabel,
  formatTradingAccountSelectorLabel,
} from "@/lib/tradeAccountDisplay"
import { formatPayoutHistoryDate } from "@/lib/propfirmPayoutCycles"
import { formatCurrency } from "@/lib/formatCurrency"

type WithdrawalHistoryRowProps = {
  item: PayoutHistoryItem
  account:
    | { id: string; name?: string | null; mode?: unknown; category?: unknown }
    | undefined
}

function kindLabel(
  item: PayoutHistoryItem,
  account: WithdrawalHistoryRowProps["account"]
): string {
  if (isPropPayoutHistoryItem(item, account)) return "Prop payout"
  if (isLiveWithdrawalHistoryItem(item, account)) return "Live withdrawal"
  return "Withdrawal"
}

export default function WithdrawalHistoryRow({
  item,
  account,
}: WithdrawalHistoryRowProps) {
  const label = account
    ? formatTradingAccountSelectorLabel(account)
    : "Account"
  const mode = account ? formatTradingAccountModeLabel(account.mode) : ""
  const dateIso =
    item.source === "fundedCycle"
      ? item.cycle?.ended_at ?? item.cycle?.started_at ?? null
      : item.payoutDate
        ? `${item.payoutDate}T12:00:00.000Z`
        : new Date(item.dateMs).toISOString()

  return (
    <Link
      href={payoutHistoryItemHref(item.id)}
      className="flex items-center justify-between gap-3 px-4 py-3 transition hover:bg-white/5"
    >
      <div className="min-w-0">
        <p className="truncate text-sm font-medium text-white">{label}</p>
        <p className="mt-0.5 text-xs text-gray-400">
          {mode ? `${mode} · ` : ""}
          {kindLabel(item, account)}
        </p>
      </div>
      <div className="shrink-0 text-right">
        <p className="text-sm font-semibold tabular-nums text-white">
          {formatCurrency(item.amount)}
        </p>
        <p className="mt-0.5 text-xs text-gray-400">
          {formatPayoutHistoryDate(dateIso)}
        </p>
      </div>
    </Link>
  )
}
