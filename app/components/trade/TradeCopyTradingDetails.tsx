"use client"

import { useMemo } from "react"
import {
  formatTradingAccountSelectorLabel,
  type AccountRowForDisplay,
} from "@/lib/tradeAccountDisplay"
import { getCopiedAccountCount, isCopyTradedMode } from "@/lib/tradeMode"

type AccountLike = AccountRowForDisplay & {
  id?: string | null
  size?: string | null
}

type TradeCopyTradingDetailsProps = {
  trade: {
    trade_mode?: unknown
    copied_account_ids?: unknown
    copy_trading_group_id?: unknown
    source_account_id?: unknown
    account_id?: unknown
    account_name?: unknown
  }
  accounts?: readonly AccountLike[]
  className?: string
}

function accountLabel(
  accountId: string,
  accounts: readonly AccountLike[],
  fallbackName?: string | null
): string {
  const matched = accounts.find((account) => String(account.id) === accountId)
  if (matched) {
    return (
      formatTradingAccountSelectorLabel({
        name: matched.name,
        size: matched.size ?? matched.account_size,
        account_number: matched.account_number,
        mode: matched.mode,
      }) ||
      String(matched.name ?? "").trim() ||
      "Account"
    )
  }
  const fallback = String(fallbackName ?? "").trim()
  return fallback || "Account"
}

export default function TradeCopyTradingDetails({
  trade,
  accounts = [],
  className = "",
}: TradeCopyTradingDetailsProps) {
  const details = useMemo(() => {
    if (!isCopyTradedMode(trade)) return null

    const sourceId = String(
      trade.source_account_id ?? trade.account_id ?? ""
    ).trim()
    const copiedIds = Array.isArray(trade.copied_account_ids)
      ? trade.copied_account_ids
          .map((id) => String(id ?? "").trim())
          .filter((id) => id && id !== sourceId)
      : []

    if (!sourceId && copiedIds.length === 0) return null

    return {
      sourceId,
      copiedIds,
      count: getCopiedAccountCount(trade),
    }
  }, [trade])

  if (!details) return null

  return (
    <div
      className={`rounded-xl border border-violet-500/20 bg-violet-500/5 p-3 ${className}`}
    >
      <h3 className="text-sm font-semibold text-violet-200">Copy Trading</h3>

      {details.sourceId ? (
        <div className="mt-2">
          <p className="text-xs font-medium text-gray-400">Source Account</p>
          <ul className="mt-1 space-y-0.5 text-sm text-gray-100">
            <li>
              •{" "}
              {accountLabel(
                details.sourceId,
                accounts,
                trade.account_name != null ? String(trade.account_name) : null
              )}
            </li>
          </ul>
        </div>
      ) : null}

      {details.copiedIds.length > 0 ? (
        <div className="mt-3">
          <p className="text-xs font-medium text-gray-400">Copied To</p>
          <ul className="mt-1 space-y-0.5 text-sm text-gray-100">
            {details.copiedIds.map((id) => (
              <li key={id}>• {accountLabel(id, accounts)}</li>
            ))}
          </ul>
        </div>
      ) : null}
    </div>
  )
}
