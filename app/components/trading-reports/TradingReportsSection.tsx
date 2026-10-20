"use client"

import {
  forwardRef,
  useCallback,
  useEffect,
  useImperativeHandle,
  useMemo,
  useState,
} from "react"
import { usePathname, useRouter, useSearchParams } from "next/navigation"
import TradingReportModal, {
  type ReportsModalTab,
} from "@/app/components/trading-reports/TradingReportModal"
import YearlyTradingReportModal from "@/app/components/trading-reports/YearlyTradingReportModal"
import TradingReportsDashboardCard from "@/app/components/trading-reports/TradingReportsDashboardCard"
import {
  PsychologyReportDetail,
  PsychologyReportsCatalog,
} from "@/app/components/trading-reports/PsychologyReportView"
import { parsePsychologyReportID } from "@/lib/psychology/reports/catalog"
import { reportIDForRef } from "@/lib/psychology/reports/periods"
import type { PsychologyReportPeriodRef } from "@/lib/psychology/reports/types"
import { usePsychologyReports } from "@/lib/usePsychologyReports"
import { useTradingReports } from "@/lib/useTradingReports"
import { tradesSelectedTradeHref } from "@/lib/tradesSelectedTrade"
import {
  parseYearlyReportParam,
  yearlyReportParam,
} from "@/lib/tradingReports/tradingYearlyReportPeriods"
import type { TradingReportPeriodKey } from "@/lib/tradingReports/tradingReportTypes"

const VALID_PERIOD_KEYS = new Set<TradingReportPeriodKey>([
  "weekly_this",
  "weekly_last",
  "monthly_this",
  "monthly_last",
])

function parsePeriodKey(value: string | null): TradingReportPeriodKey | null {
  if (!value) return null
  return VALID_PERIOD_KEYS.has(value as TradingReportPeriodKey)
    ? (value as TradingReportPeriodKey)
    : null
}

function parseReportSearch(value: string | null): {
  tab: ReportsModalTab
  periodKey?: TradingReportPeriodKey
  psychologyRef?: PsychologyReportPeriodRef
  yearlyYear?: number
  yearlyCatalog?: boolean
} | null {
  if (!value) return null
  if (value === "psychology") return { tab: "psychology" }
  if (value === "yearly") return { tab: "performance", yearlyCatalog: true }
  const yearlyYear = parseYearlyReportParam(value)
  if (yearlyYear != null) return { tab: "performance", yearlyYear }
  const periodKey = parsePeriodKey(value)
  if (periodKey) return { tab: "performance", periodKey }
  const parsed = parsePsychologyReportID(value)
  if (parsed) return { tab: "psychology", psychologyRef: parsed }
  return null
}

type TradingReportsSectionProps = {
  userId: string | null | undefined
  trades: any[]
}

export type TradingReportsSectionHandle = {
  openReport: () => void
  openPeriod: (key: TradingReportPeriodKey) => void
  openPsychology: (reportId?: string) => void
}

const TradingReportsSection = forwardRef<
  TradingReportsSectionHandle,
  TradingReportsSectionProps
>(function TradingReportsSection({ userId, trades }, ref) {
  const searchParams = useSearchParams()
  const router = useRouter()
  const pathname = usePathname()
  const { snapshot, loading, newBadge, getReport, markSeen } = useTradingReports(
    userId,
    trades
  )

  const [open, setOpen] = useState(false)
  const [tab, setTab] = useState<ReportsModalTab>("performance")
  const [periodKey, setPeriodKey] = useState<TradingReportPeriodKey>("weekly_this")
  const [psychologyRef, setPsychologyRef] = useState<PsychologyReportPeriodRef | null>(
    null
  )
  const [yearlyOpen, setYearlyOpen] = useState(false)
  const [yearlyYear, setYearlyYear] = useState<number | null>(null)

  const psychology = usePsychologyReports(userId, trades, open && tab === "psychology")

  const report = useMemo(
    () => getReport(periodKey) ?? snapshot?.reports[periodKey] ?? null,
    [getReport, periodKey, snapshot]
  )

  const bestTrade = useMemo(() => {
    if (!report?.bestTradeId) return null
    return trades.find((trade) => String(trade.id) === report.bestTradeId) ?? null
  }, [report?.bestTradeId, trades])

  const writeReportParam = useCallback(
    (value: string | null) => {
      const next = new URLSearchParams(searchParams.toString())
      if (value) next.set("report", value)
      else next.delete("report")
      const qs = next.toString()
      router.replace(qs ? `${pathname}?${qs}` : pathname, { scroll: false })
    },
    [pathname, router, searchParams]
  )

  const openModal = useCallback(
    (key?: TradingReportPeriodKey) => {
      const nextKey = key ?? periodKey
      setPeriodKey(nextKey)
      setTab("performance")
      setPsychologyRef(null)
      setOpen(true)
      writeReportParam(nextKey)
      if (userId) {
        if (nextKey === "weekly_last" || nextKey === "monthly_last") {
          markSeen(nextKey)
        }
      }
    },
    [markSeen, periodKey, userId, writeReportParam]
  )

  const openPsychology = useCallback(
    (reportId?: string) => {
      setTab("psychology")
      setOpen(true)
      if (reportId) {
        const parsed = parsePsychologyReportID(reportId)
        setPsychologyRef(parsed)
        writeReportParam(reportId)
      } else {
        setPsychologyRef(null)
        writeReportParam("psychology")
      }
    },
    [writeReportParam]
  )

  const openDefaultReport = useCallback(() => {
    openModal(
      newBadge?.kind === "monthly"
        ? "monthly_last"
        : newBadge?.kind === "weekly"
          ? "weekly_last"
          : "weekly_this"
    )
  }, [newBadge, openModal])

  const handleViewTrade = useCallback(
    (trade: { id?: string | null }) => {
      const id = String(trade?.id ?? "").trim()
      if (!id) return
      router.push(tradesSelectedTradeHref(id))
    },
    [router]
  )

  useImperativeHandle(
    ref,
    () => ({
      openReport: openDefaultReport,
      openPeriod: (key: TradingReportPeriodKey) => openModal(key),
      openPsychology: (reportId?: string) => openPsychology(reportId),
    }),
    [openDefaultReport, openModal, openPsychology]
  )

  useEffect(() => {
    const parsed = parseReportSearch(searchParams.get("report"))
    if (!parsed) return
    if (parsed.yearlyCatalog || parsed.yearlyYear != null) {
      setYearlyYear(parsed.yearlyYear ?? null)
      setYearlyOpen(true)
      return
    }
    setOpen(true)
    setTab(parsed.tab)
    if (parsed.periodKey) setPeriodKey(parsed.periodKey)
    if (parsed.psychologyRef) setPsychologyRef(parsed.psychologyRef)
    if (parsed.tab === "psychology" && !parsed.psychologyRef) {
      setPsychologyRef(null)
    }
  }, [searchParams])

  useEffect(() => {
    if (!open || !userId) return
    if (periodKey === "weekly_last" || periodKey === "monthly_last") {
      markSeen(periodKey)
    }
  }, [open, periodKey, markSeen, userId])

  const selectedPsychologyReport = psychologyRef
    ? psychology.getReport(psychologyRef)
    : null
  const selectedPsychologyPeriods = psychologyRef
    ? psychology.cards.find((card) => card.template === psychologyRef.template)
        ?.availablePeriods ?? [psychologyRef]
    : []

  if (!userId) return null

  return (
    <>
      <div className="tt-dash-hide-desktop-v1 hidden md:block">
        <TradingReportsDashboardCard
          onOpen={openDefaultReport}
          loading={loading && !snapshot}
          newBadge={newBadge}
        />
      </div>

      <YearlyTradingReportModal
        open={yearlyOpen}
        onClose={() => {
          setYearlyOpen(false)
          setYearlyYear(null)
          writeReportParam(null)
        }}
        trades={trades}
        initialYear={yearlyYear}
        onYearChange={(year) => {
          setYearlyYear(year)
          if (year != null) writeReportParam(yearlyReportParam(year))
          else writeReportParam("yearly")
        }}
        viewerUserId={userId}
        onViewTrade={handleViewTrade}
      />

      <TradingReportModal
        open={open}
        onClose={() => {
          setOpen(false)
          setPsychologyRef(null)
          writeReportParam(null)
        }}
        onOpenYearlyReports={() => {
          setOpen(false)
          setYearlyOpen(true)
          setYearlyYear(null)
          writeReportParam("yearly")
        }}
        report={report}
        periodKey={periodKey}
        onPeriodChange={(key) => {
          setPeriodKey(key)
          writeReportParam(key)
        }}
        bestTrade={bestTrade}
        viewerUserId={userId}
        onViewTrade={handleViewTrade}
        tab={tab}
        onTabChange={(next) => {
          setTab(next)
          if (next === "psychology") {
            writeReportParam(
              psychologyRef ? reportIDForRef(psychologyRef) : "psychology"
            )
          } else {
            writeReportParam(periodKey)
          }
        }}
        psychologyContent={
          psychology.loadError && !psychology.ready ? (
            <p className="text-sm text-red-400">{psychology.loadError}</p>
          ) : !psychology.ready || psychology.loading ? (
            <div className="rounded-xl border border-white/10 bg-white/5 p-6 text-center text-gray-300">
              Loading psychology reports…
            </div>
          ) : selectedPsychologyReport && psychologyRef ? (
            <div className="space-y-4">
              <button
                type="button"
                className="text-xs font-medium text-blue-300 underline"
                onClick={() => {
                  setPsychologyRef(null)
                  writeReportParam("psychology")
                }}
              >
                All psychology reports
              </button>
              <PsychologyReportDetail
                report={selectedPsychologyReport}
                periods={selectedPsychologyPeriods}
                onPeriodChange={(ref) => {
                  setPsychologyRef(ref)
                  writeReportParam(reportIDForRef(ref))
                }}
              />
            </div>
          ) : (
            <div className="space-y-3">
              <div>
                <h2 className="text-xl font-semibold text-white">Psychology Reports</h2>
                <p className="text-sm text-gray-400">
                  Patterns from your trades and daily check-ins
                </p>
              </div>
              {psychology.loadError ? (
                <p className="text-sm text-red-400">
                  {psychology.loadError}{" "}
                  <button type="button" className="underline" onClick={() => void psychology.refresh()}>
                    Retry
                  </button>
                </p>
              ) : null}
              <PsychologyReportsCatalog
                cards={psychology.cards}
                onOpen={(ref) => {
                  setPsychologyRef(ref)
                  writeReportParam(reportIDForRef(ref))
                }}
              />
            </div>
          )
        }
      />
    </>
  )
})

export default TradingReportsSection
