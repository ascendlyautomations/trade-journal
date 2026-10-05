"use client"

import { useMemo } from "react"
import {
  formatTradingAccountSelectorLabel,
  safeAccountNumberLabel,
  type AccountRowForDisplay,
} from "@/lib/tradeAccountDisplay"
import type { CopyTradeWireRow } from "@/lib/copyTradePresentation"

type CopyTradeTradesPageAccountsProps = {
  members: readonly CopyTradeWireRow[]
  accounts: readonly AccountRowForDisplay[]
  className?: string
}

function accountLine(
  trade: CopyTradeWireRow,
  accounts: readonly AccountRowForDisplay[]
): string {
  const accountId = String(trade.account_id ?? "").trim()
  const matched = accounts.find((row) => String(row.id) === accountId)
  const name = matched?.name ?? trade.account_name
  const label =
    formatTradingAccountSelectorLabel({
      name: name != null ? String(name) : null,
      size: matched?.account_size ?? trade.account_size,
      account_number: matched?.account_number ?? trade.account_number,
      mode: matched?.mode ?? trade.mode ?? trade.account_type,
    }) || String(name ?? "Account").trim()
  const modeLabel = String(matched?.mode ?? trade.mode ?? trade.account_type ?? "")
    .trim()
  const num = safeAccountNumberLabel(
    matched?.account_number ?? trade.account_number
  )
  const parts = [label]
  if (modeLabel) parts.push(modeLabel.charAt(0).toUpperCase() + modeLabel.slice(1))
  if (num) parts.push(`•••${num}`)
  return parts.join(" • ")
}

/** Private Trades page — participating accounts for one copy action. */
export default function CopyTradeTradesPageAccounts({
  members,
  accounts,
  className = "",
}: CopyTradeTradesPageAccountsProps) {
  const lines = useMemo(() => {
    const seen = new Set<string>()
    const out: string[] = []
    for (const member of members) {
      const id = String(member.account_id ?? member.id ?? "").trim()
      if (!id || seen.has(id)) continue
      seen.add(id)
      out.push(accountLine(member, accounts))
    }
    return out
  }, [members, accounts])

  if (lines.length === 0) return null

  return (
    <ul className={`space-y-0.5 text-xs text-gray-300 md:text-sm ${className}`}>
      {lines.map((line) => (
        <li key={line} className="truncate">
          {line}
        </li>
      ))}
    </ul>
  )
}
