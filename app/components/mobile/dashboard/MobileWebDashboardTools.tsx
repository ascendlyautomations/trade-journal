"use client"

import Link from "next/link"
import { BarChart3, List, Wallet } from "lucide-react"

type MobileWebDashboardToolsProps = {
  onOpenReports?: () => void
  reportsDisabled?: boolean
}

const toolClass =
  "inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-white/10 text-white"

export default function MobileWebDashboardTools({
  onOpenReports,
  reportsDisabled = false,
}: MobileWebDashboardToolsProps) {
  return (
    <div className="flex shrink-0 items-center gap-1">
      <Link href="/trades" aria-label="Trades" className={toolClass}>
        <List className="h-5 w-5" strokeWidth={1.9} aria-hidden />
      </Link>
      {onOpenReports ? (
        <button
          type="button"
          aria-label="Reports"
          disabled={reportsDisabled}
          onClick={onOpenReports}
          className={`${toolClass} disabled:opacity-40`}
        >
          <BarChart3 className="h-5 w-5" strokeWidth={1.9} aria-hidden />
        </button>
      ) : null}
      <Link href="/withdrawals" aria-label="Withdrawals" className={toolClass}>
        <Wallet className="h-5 w-5" strokeWidth={1.9} aria-hidden />
      </Link>
    </div>
  )
}
