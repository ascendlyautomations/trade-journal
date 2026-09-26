"use client"

import Link from "next/link"
import { useEffect, useMemo, useState } from "react"
import {
  buildDashboardPropFirmSnapshot,
  propFirmDetailsHref,
  type DashboardPropFirmAccount,
  type DashboardPropFirmSnapshot,
  type DashboardPropFirmTone,
} from "@/lib/dashboardPropFirmContext"
import { readPropFirmBootstrapCache } from "@/lib/backendV2/propFirmBootstrapCache"
import { snapshotPropFirmBootstrapPageData } from "@/lib/backendV2/propFirmBootstrapRepository"
import type { PropfirmTrade } from "@/lib/propfirmMetrics"
import {
  fetchPayoutCycleHistoryByAccountIds,
  isFundedPropfirmAccount,
  type AccountPayoutCycle,
} from "@/lib/propfirmPayoutCycles"
import { supabase } from "@/lib/supabaseClient"

type DashboardPropFirmDetailsProps = {
  account: DashboardPropFirmAccount
  trades: PropfirmTrade[]
  userId: string | null
}

function toneClass(tone: DashboardPropFirmTone): string {
  if (tone === "positive") return "text-green-300 bg-green-400/10"
  if (tone === "negative") return "text-red-300 bg-red-400/10"
  return "text-blue-200 bg-blue-400/10"
}

function Metric({
  label,
  value,
  valueClassName = "text-white",
}: {
  label: string
  value: string
  valueClassName?: string
}) {
  return (
    <div className="min-w-0">
      <p className="text-[11px] text-gray-400">{label}</p>
      <p className={`mt-0.5 truncate text-sm font-semibold tabular-nums ${valueClassName}`}>
        {value}
      </p>
    </div>
  )
}

function ProgressRow({
  label,
  value,
  progress,
  met,
}: {
  label: string
  value: string
  progress: number
  met?: boolean
}) {
  const width = `${Math.min(Math.max(progress, 0), 100)}%`
  const bar =
    met === false ? "bg-amber-300" : met === true ? "bg-green-400" : "bg-sky-300"
  return (
    <div>
      <div className="mb-1 flex items-center justify-between gap-3 text-[11px]">
        <span className="text-gray-400">{label}</span>
        <span className="tabular-nums text-gray-200">{value}</span>
      </div>
      <div className="h-1.5 overflow-hidden rounded-full bg-white/10">
        <div className={`h-full rounded-full ${bar}`} style={{ width }} />
      </div>
    </div>
  )
}

function DetailsBody({ snapshot }: { snapshot: DashboardPropFirmSnapshot }) {
  return (
    <>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        <Metric label="Account Balance" value={snapshot.balanceLabel} />
        {snapshot.profitTarget ? (
          <Metric
            label="Profit Target"
            value={snapshot.profitTarget.remainingLabel}
            valueClassName="text-emerald-300"
          />
        ) : null}
        {snapshot.drawdown ? (
          <Metric
            label="Drawdown Remaining"
            value={snapshot.drawdown.remainingLabel}
            valueClassName={
              snapshot.drawdown.danger ? "text-red-300" : "text-white"
            }
          />
        ) : null}
        {snapshot.consistency ? (
          <Metric
            label="Consistency"
            value={snapshot.consistency.percentLabel}
            valueClassName={
              snapshot.consistency.met ? "text-green-300" : "text-amber-200"
            }
          />
        ) : null}
        {snapshot.winningDays ? (
          <Metric label="Winning Days" value={snapshot.winningDays.label} />
        ) : null}
        <Metric
          label="Status"
          value={snapshot.statusLabel}
          valueClassName={
            snapshot.statusTone === "positive"
              ? "text-green-300"
              : snapshot.statusTone === "negative"
                ? "text-red-300"
                : "text-white"
          }
        />
      </div>
      <div className="mt-3 space-y-2.5">
        {snapshot.profitTarget ? (
          <ProgressRow
            label="Profit target"
            value={`${Math.round(snapshot.profitTarget.progress)}%`}
            progress={snapshot.profitTarget.progress}
          />
        ) : null}
        {snapshot.drawdown ? (
          <ProgressRow
            label="Drawdown used"
            value={snapshot.drawdown.danger ? "At risk" : "Within limit"}
            progress={snapshot.drawdown.usedProgress}
            met={!snapshot.drawdown.danger}
          />
        ) : null}
        {snapshot.winningDays ? (
          <ProgressRow
            label="Winning days"
            value={snapshot.winningDays.label}
            progress={snapshot.winningDays.progress}
            met={snapshot.winningDays.met}
          />
        ) : null}
      </div>
    </>
  )
}

export default function DashboardPropFirmDetails({
  account,
  trades,
  userId,
}: DashboardPropFirmDetailsProps) {
  const funded = isFundedPropfirmAccount(account.mode)
  const [cycles, setCycles] = useState<AccountPayoutCycle[] | null>(
    funded ? null : []
  )
  const [failed, setFailed] = useState(false)
  const href = propFirmDetailsHref(account.id)

  useEffect(() => {
    if (!funded) {
      setCycles([])
      setFailed(false)
      return
    }

    let cancelled = false
    setFailed(false)
    const cached = userId ? readPropFirmBootstrapCache(userId) : null
    if (cached) {
      const snapshot = snapshotPropFirmBootstrapPageData(cached, [account.id])
      setCycles(snapshot.payoutCyclesByAccountId[account.id] ?? [])
      return
    }

    setCycles(null)
    void fetchPayoutCycleHistoryByAccountIds(supabase, [account.id])
      .then((grouped) => {
        if (cancelled) return
        setCycles(grouped[account.id] ?? [])
      })
      .catch(() => {
        if (!cancelled) setFailed(true)
      })

    return () => {
      cancelled = true
    }
  }, [account.id, funded, userId])

  const snapshot = useMemo(() => {
    if (!cycles) return null
    return buildDashboardPropFirmSnapshot(account, trades, cycles)
  }, [account, trades, cycles])

  return (
    <section
      aria-label="Prop Firm Details"
      className="rounded-xl border border-white/10 bg-white/10 p-4"
    >
      <div className="mb-3 flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-blue-300">
            Prop Firm Details
          </p>
          <p className="mt-1 truncate text-sm font-semibold text-white">
            {snapshot?.heading ?? account.name ?? "Account"}
            <span className="font-medium text-gray-300">
              {" "}
              · {funded ? "Funded" : "Eval"}
            </span>
          </p>
        </div>
        <div className="flex shrink-0 items-center gap-3">
          {snapshot ? (
            <span
              className={`rounded-full px-2 py-0.5 text-[11px] font-semibold ${toneClass(snapshot.statusTone)}`}
            >
              {snapshot.statusLabel}
            </span>
          ) : null}
          <Link
            href={href}
            className="text-xs font-medium text-blue-300 transition hover:text-blue-200"
          >
            View Details →
          </Link>
        </div>
      </div>

      {failed ? (
        <p className="text-sm text-gray-300">Unable to load prop firm details.</p>
      ) : snapshot ? (
        <DetailsBody snapshot={snapshot} />
      ) : (
        <div className="space-y-3" aria-hidden="true">
          <div className="grid grid-cols-3 gap-3">
            <div className="h-8 animate-pulse rounded bg-white/10" />
            <div className="h-8 animate-pulse rounded bg-white/10" />
            <div className="h-8 animate-pulse rounded bg-white/10" />
          </div>
          <div className="h-2 animate-pulse rounded-full bg-white/10" />
        </div>
      )}
    </section>
  )
}
