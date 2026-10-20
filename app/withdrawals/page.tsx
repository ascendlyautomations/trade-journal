"use client"

import "../utilityDesktopTheme.css"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { useMemo, useState } from "react"
import EmptyState from "@/app/components/ui/EmptyState"
import TradeAccountPicker from "@/app/components/TradeAccountPicker"
import WithdrawalHistoryRow from "@/app/components/withdrawals/WithdrawalHistoryRow"
import WithdrawalsCalendar from "@/app/components/withdrawals/WithdrawalsCalendar"
import WithdrawalsEquityCurve from "@/app/components/withdrawals/WithdrawalsEquityCurve"
import { CREATE_ROUTE } from "@/lib/createRoutes"
import { formatCurrency } from "@/lib/formatCurrency"
import {
  filterLiveWithdrawals,
  filterPropPayouts,
  payoutHistorySummary,
} from "@/lib/payoutHistory"
import { useWithdrawalsHistory } from "@/lib/useWithdrawalsHistory"
import { useUserProfile } from "@/lib/useUserProfile"
import { useScrollPageTopOnMount } from "@/lib/useScrollPageTopOnMount"
import {
  buildCumulativeWithdrawalChartPoints,
  buildWithdrawalsAccountFilterOptions,
  filterPayoutHistoryByAccountFilter,
  filterPayoutHistoryBySelectedDate,
  groupWithdrawalsByDateKey,
} from "@/lib/withdrawalsPresentation"

export default function WithdrawalsPage() {
  useScrollPageTopOnMount()
  const router = useRouter()
  const { user, loading: profileLoading } = useUserProfile()
  const { loading, error, loadWarnings, items, accounts, accountsById, refresh } =
    useWithdrawalsHistory(user?.id)

  const [accountFilter, setAccountFilter] = useState("all")
  const [selectedDateKey, setSelectedDateKey] = useState<string | null>(null)

  const accountOptions = useMemo(
    () => buildWithdrawalsAccountFilterOptions(accounts),
    [accounts]
  )

  const filteredByAccount = useMemo(
    () => filterPayoutHistoryByAccountFilter(items, accountFilter),
    [items, accountFilter]
  )

  const filteredItems = useMemo(
    () => filterPayoutHistoryBySelectedDate(filteredByAccount, selectedDateKey),
    [filteredByAccount, selectedDateKey]
  )

  const summary = useMemo(
    () => payoutHistorySummary(filteredByAccount),
    [filteredByAccount]
  )

  const chartPoints = useMemo(
    () => buildCumulativeWithdrawalChartPoints(filteredByAccount),
    [filteredByAccount]
  )

  const byDate = useMemo(
    () => groupWithdrawalsByDateKey(filteredByAccount),
    [filteredByAccount]
  )

  const liveItems = useMemo(
    () => filterLiveWithdrawals(filteredItems, accountsById),
    [filteredItems, accountsById]
  )
  const propItems = useMemo(
    () => filterPropPayouts(filteredItems, accountsById),
    [filteredItems, accountsById]
  )

  if (!profileLoading && !user) {
    router.replace("/login")
    return null
  }

  const showInitialLoading =
    (profileLoading || loading) && items.length === 0 && !error

  return (
    <div className="tt-phase4-dark min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">
      <div className="mx-auto max-w-3xl px-4 py-8 sm:px-6 lg:py-10">
        <div className="mb-6 flex flex-wrap items-start justify-between gap-4">
          <div>
            <Link
              href="/app"
              className="text-sm text-blue-300 hover:text-blue-200"
            >
              ← Dashboard
            </Link>
            <h1 className="mt-2 text-2xl font-bold text-blue-300 sm:text-3xl">
              Withdrawals
            </h1>
            <p className="mt-1 text-sm text-gray-400">
              Live ledger withdrawals and funded prop-firm payout cycles. Affiliate
              payouts are on{" "}
              <Link href="/payouts" className="text-blue-300 hover:underline">
                Affiliate Payouts
              </Link>
              .
            </p>
          </div>
          <Link
            href={CREATE_ROUTE.withdrawal}
            className="shrink-0 rounded-xl bg-blue-500 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-600"
          >
            Record withdrawal
          </Link>
        </div>

        <div className="mb-6">
          <TradeAccountPicker
            accounts={[]}
            isPro={false}
            copyGroups={[]}
            filterValue={accountFilter}
            filterOptions={accountOptions}
            onFilterChange={(value) => {
              setAccountFilter(value)
              setSelectedDateKey(null)
            }}
            filterPlaceholder="All Accounts"
            showExternalCreateButton={false}
            hideManageAccounts
          />
        </div>

        {error ? (
          <div className="mb-6 rounded-xl border border-red-500/30 bg-red-500/10 px-4 py-3 text-sm text-red-100">
            {error}
            <button
              type="button"
              onClick={() => void refresh()}
              className="ml-2 underline"
            >
              Retry
            </button>
          </div>
        ) : null}

        {!error && loadWarnings.length > 0 ? (
          <div className="mb-6 space-y-2 rounded-xl border border-amber-500/30 bg-amber-500/10 px-4 py-3 text-sm text-amber-100">
            {loadWarnings.map((message) => (
              <p key={message}>{message}</p>
            ))}
            <button
              type="button"
              onClick={() => void refresh()}
              className="underline"
            >
              Retry
            </button>
          </div>
        ) : null}

        <div className="mb-6 space-y-6">
          <div className="rounded-xl border border-white/10 bg-white/5 px-5 py-4">
            <p className="text-sm text-gray-400">Total withdrawn</p>
            <p className="mt-1 text-2xl font-semibold tabular-nums text-white">
              {formatCurrency(summary.total)}
            </p>
            {summary.count > 0 ? (
              <p className="mt-1 text-xs text-gray-400">
                {summary.count} recorded across Live and Prop accounts
                {accountFilter !== "all" ? " (filtered)" : ""}
              </p>
            ) : null}
          </div>

          {showInitialLoading ? (
            <p className="text-sm text-gray-400">Loading withdrawals…</p>
          ) : filteredByAccount.length === 0 && !error ? (
            <EmptyState
              title="No withdrawals yet"
              description="Withdrawals you record from Create will appear here."
            />
          ) : (
            <>
              <WithdrawalsEquityCurve
                data={chartPoints}
                totalWithdrawn={summary.total}
              />
              <WithdrawalsCalendar
                byDate={byDate}
                selectedDateKey={selectedDateKey}
                onSelectDateKey={setSelectedDateKey}
              />
            </>
          )}
        </div>

        {!showInitialLoading && filteredItems.length > 0 ? (
          <div className="space-y-8">
            {liveItems.length > 0 ? (
              <section>
                <h2 className="mb-2 px-1 text-sm font-semibold uppercase tracking-wide text-gray-400">
                  Live withdrawals
                </h2>
                <ul className="divide-y divide-white/10 overflow-hidden rounded-xl border border-white/10 bg-white/5">
                  {liveItems.map((item) => (
                    <li key={item.id}>
                      <WithdrawalHistoryRow
                        item={item}
                        account={accountsById[item.accountId]}
                      />
                    </li>
                  ))}
                </ul>
              </section>
            ) : null}

            {propItems.length > 0 ? (
              <section>
                <h2 className="mb-2 px-1 text-sm font-semibold uppercase tracking-wide text-gray-400">
                  Prop payouts
                </h2>
                <ul className="divide-y divide-white/10 overflow-hidden rounded-xl border border-white/10 bg-white/5">
                  {propItems.map((item) => (
                    <li key={item.id}>
                      <WithdrawalHistoryRow
                        item={item}
                        account={accountsById[item.accountId]}
                      />
                    </li>
                  ))}
                </ul>
              </section>
            ) : null}

            {filteredItems.length === 0 && filteredByAccount.length > 0 ? (
              <p className="text-center text-sm text-gray-400">
                No withdrawals on the selected date.
              </p>
            ) : null}
          </div>
        ) : null}
      </div>
    </div>
  )
}
