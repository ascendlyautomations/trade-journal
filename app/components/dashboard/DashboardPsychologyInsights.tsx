"use client"

import Link from "next/link"
import { useRouter } from "next/navigation"
import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react"
import { createPortal } from "react-dom"
import { useProUpgradeOptional } from "@/app/components/monetization/ProUpgradeProvider"
import {
  PSYCHOLOGY_JOURNAL_EMPTY_DASHBOARD_TRADES,
  usePsychologyJournalInputs,
} from "@/lib/psychology/usePsychologyJournalInputs"
import { buildDashboardPsychologyStats } from "@/lib/psychology/dashboardStats"
import { focusPsychologySection } from "@/lib/psychology/psychologySessionStore"
import { psychologySectionIdForCategory } from "@/lib/psychology/sectionId"
import { hydratePsychologySession } from "@/lib/psychology/hydratePsychologySession"
import { setPsychologyAnalyticsScope } from "@/lib/psychology/psychologySessionStore"
import { createPsychologyAnalyticsScope } from "@/lib/psychology/psychologyScope"
import {
  buildEarlyPsychologyInsightCards,
  hasMatchedPsychologyData,
  mergePsychologyInsightCards,
} from "@/lib/psychology/dailyPsychologyInsights"
import {
  displayCheckInDayCountForGate,
  displayTradeCountForGate,
  PSYCHOLOGY_INSIGHTS_REQUIRED_COUNT,
} from "@/lib/psychology/unlockProgress"
import { reliabilityLabel } from "@/lib/psychology/reports/metrics"
import type { PsychologyInsightCard } from "@/lib/psychology/reports/types"
import { useUserProfile } from "@/lib/useUserProfile"
import { useProGate } from "@/lib/useProGate"
import { dashboardInsightCardClass } from "./dashboardInsightStyles"
import type { DashboardTradeRow } from "./dashboardTypes"

const INSIGHT_PREVIEW_COUNT = 2

type DashboardPsychologyInsightsProps = {
  userId: string
  trades: DashboardTradeRow[]
  /** False while Dashboard trades have not been hydrated — avoids a 0/5 flash. */
  tradesReady?: boolean
  /** Matches dashboard filters — keeps analytics scope aligned with this widget. */
  scopeLabel?: string
}

/** One instance is portaled into the slot for the active dashboard layout. */
export const PSYCHOLOGY_INSIGHTS_SLOT_ID = {
  desktop: "tt-dash-psych-slot-desktop",
  tablet: "tt-dash-psych-slot-tablet",
  mobile: "tt-dash-psych-slot-mobile",
} as const

export function DashboardPsychologyInsightsSlot({
  slot,
}: {
  slot: keyof typeof PSYCHOLOGY_INSIGHTS_SLOT_ID
}) {
  return <div id={PSYCHOLOGY_INSIGHTS_SLOT_ID[slot]} className="tt-dash-psych-slot" />
}

export function DashboardPsychologyInsightsPlacement({
  children,
  placementKey,
}: {
  children: ReactNode
  placementKey: string
}) {
  const [target, setTarget] = useState<HTMLElement | null>(null)
  const [ready, setReady] = useState(false)

  const resolveSlot = useCallback((): HTMLElement | null => {
    const desktop = window.matchMedia("(min-width: 1200px)")
    const tablet = window.matchMedia("(min-width: 768px) and (max-width: 1199px)")
    const id = desktop.matches
      ? PSYCHOLOGY_INSIGHTS_SLOT_ID.desktop
      : tablet.matches
        ? PSYCHOLOGY_INSIGHTS_SLOT_ID.tablet
        : PSYCHOLOGY_INSIGHTS_SLOT_ID.mobile
    return document.getElementById(id)
  }, [])

  useLayoutEffect(() => {
    const desktop = window.matchMedia("(min-width: 1200px)")
    const tablet = window.matchMedia("(min-width: 768px) and (max-width: 1199px)")

    const pick = () => {
      setTarget(resolveSlot())
      setReady(true)
    }

    pick()
    desktop.addEventListener("change", pick)
    tablet.addEventListener("change", pick)
    return () => {
      desktop.removeEventListener("change", pick)
      tablet.removeEventListener("change", pick)
    }
  }, [placementKey, resolveSlot])

  useEffect(() => {
    if (target) return
    let cancelled = false
    let attempts = 0
    const maxAttempts = 180

    const tick = () => {
      if (cancelled) return
      const node = resolveSlot()
      if (node) {
        setTarget(node)
        return
      }
      attempts += 1
      if (attempts < maxAttempts) {
        requestAnimationFrame(tick)
      }
    }

    requestAnimationFrame(tick)
    return () => {
      cancelled = true
    }
  }, [target, placementKey, resolveSlot])

  if (!ready) return null
  if (target) return createPortal(children, target)
  return <div className="tt-dash-psych-fallback mt-2 md:mt-3">{children}</div>
}

export function DashboardPsychologyInsightsSkeleton() {
  return (
    <div
      className="tt-dash-psych-metric h-24 animate-pulse rounded-xl border border-white/10 bg-white/5"
      aria-hidden
    />
  )
}

function PsychologyUpgradeSection() {
  const upgrade = useProUpgradeOptional()
  return (
    <div
      className="tt-dash-psych-upgrade rounded-xl border border-white/10 bg-white/5 p-4"
      data-testid="dashboard.psychology.upgrade.traxpro"
    >
      <h3 className="text-sm font-semibold text-white">TraxPro psychology analytics</h3>
      <p className="mt-1 text-xs text-gray-400">
        Advanced psychology analytics and coaching are included with TraxPro.
      </p>
      <button
        type="button"
        className="mt-3 w-full rounded-lg bg-blue-500 px-4 py-2.5 text-sm font-semibold text-white"
        onClick={() =>
          upgrade?.presentProUpgrade({
            reason: { type: "feature", feature: "premium_analytics" },
          })
        }
      >
        Upgrade to TraxPro
      </button>
    </div>
  )
}

function PsychologyInsightCardRow({
  card,
  onSelect,
}: {
  card: PsychologyInsightCard
  onSelect: () => void
}) {
  return (
    <button
      type="button"
      onClick={onSelect}
      className={`${dashboardInsightCardClass} flex w-full items-start gap-3 text-left`}
      data-testid={`dashboard.psychologyInsight.${card.id}`}
    >
      <span
        className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-blue-500/15 text-sm text-blue-300"
        aria-hidden
      >
        ◎
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-[10px] font-semibold uppercase tracking-wide text-blue-400">
          {card.sectionTitle}
        </span>
        <span className="mt-0.5 block text-sm font-semibold text-white">{card.headline}</span>
        <span className="mt-0.5 block text-xs text-gray-400">{card.detail}</span>
        <span className="mt-1 block text-[10px] text-gray-500">
          {reliabilityLabel(card.reliability)}
          {card.sampleSize > 0 ? ` · ${card.sampleSize} trades` : ""}
        </span>
      </span>
      <span className="shrink-0 text-xs text-gray-500" aria-hidden>
        ›
      </span>
    </button>
  )
}

export default function DashboardPsychologyInsights({
  userId,
  trades,
  tradesReady = true,
  scopeLabel = "Dashboard filters",
}: DashboardPsychologyInsightsProps) {
  const router = useRouter()
  const { profile } = useUserProfile()
  const { proFeatureUnlocked } = useProGate(profile)
  const { checkIns, ready, loadError, refresh } = usePsychologyJournalInputs(
    userId,
    PSYCHOLOGY_JOURNAL_EMPTY_DASHBOARD_TRADES
  )
  const [reportReady, setReportReady] = useState(true)
  const [cards, setCards] = useState<PsychologyInsightCard[]>([])

  const stats = useMemo(
    () => buildDashboardPsychologyStats(trades, checkIns),
    [trades, checkIns]
  )

  const tradeRecords = useMemo(
    () => trades as ReadonlyArray<Record<string, unknown>>,
    [trades]
  )

  useEffect(() => {
    if (!ready || !tradesReady || !proFeatureUnlocked) {
      return
    }
    let cancelled = false
    void (async () => {
      try {
        setPsychologyAnalyticsScope(
          createPsychologyAnalyticsScope(userId, scopeLabel, tradeRecords)
        )
        const snapshot = await hydratePsychologySession(userId, tradeRecords, {
          scopeLabel,
        })
        if (cancelled) return
        setCards(snapshot.report?.dashboardCards ?? [])
      } catch {
        if (!cancelled) {
          setCards([])
        }
      } finally {
        if (!cancelled) setReportReady(true)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [
    checkIns,
    ready,
    proFeatureUnlocked,
    scopeLabel,
    tradeRecords,
    tradesReady,
    userId,
  ])

  const displayCards = useMemo(() => {
    const early = buildEarlyPsychologyInsightCards(trades, checkIns)
    return mergePsychologyInsightCards(early, cards)
  }, [trades, checkIns, cards])

  const hasMatched = useMemo(
    () => hasMatchedPsychologyData(trades, checkIns),
    [trades, checkIns]
  )

  if (!ready || !tradesReady) {
    return <DashboardPsychologyInsightsSkeleton />
  }

  const { unlock } = stats

  function openAnalytics(highlightSection: string | null) {
    setPsychologyAnalyticsScope(
      createPsychologyAnalyticsScope(userId, scopeLabel, tradeRecords)
    )
    focusPsychologySection(highlightSection)
    const query = highlightSection
      ? `?section=${encodeURIComponent(highlightSection)}`
      : ""
    router.push(`/psychology/analytics${query}`)
  }

  return (
    <section className="tt-dash-psych" data-testid="dashboard.psychologyInsights">
      <div className="mb-3 flex items-start justify-between gap-2">
        <div>
          <h2 className="tt-dash-section-title">Psychology Insights</h2>
          <p className="tt-dash-section-subtitle">
            Patterns from your trades and daily check-ins
          </p>
        </div>
        {proFeatureUnlocked ? (
          <Link
            href="/psychology/analytics"
            className="shrink-0 text-xs font-semibold text-blue-400 hover:text-blue-300"
            data-testid="dashboard.psychologyInsights.seeAll"
            onClick={() =>
              setPsychologyAnalyticsScope(
                createPsychologyAnalyticsScope(userId, scopeLabel, tradeRecords)
              )
            }
          >
            See all
          </Link>
        ) : null}
      </div>

      {loadError && checkIns.length === 0 ? (
        <p className="text-xs text-red-400">
          {loadError}{" "}
          <button type="button" className="underline" onClick={() => void refresh()}>
            Retry
          </button>
        </p>
      ) : !proFeatureUnlocked ? (
        <PsychologyUpgradeSection />
      ) : !reportReady ? (
        <DashboardPsychologyInsightsSkeleton />
      ) : displayCards.length === 0 ? (
        <div
          className="rounded-xl border border-white/10 bg-white/5 p-4"
          data-testid="dashboard.psychologyInsights.empty"
        >
          <p className="text-sm font-medium text-white">No matched days yet</p>
          <p className="mt-1 text-xs text-gray-400">
            Log a daily check-in on the same Eastern calendar day as a trade in this
            filter scope to see sleep, mood, and performance relationships.
          </p>
          {!hasMatched && trades.length > 0 && checkIns.length > 0 ? (
            <p className="mt-2 text-xs text-gray-500">
              You have trades and check-ins, but none share the same trading day yet.
            </p>
          ) : null}
        </div>
      ) : (
        <>
          {unlock.tradingDayCheckInCount < PSYCHOLOGY_INSIGHTS_REQUIRED_COUNT ||
          unlock.tradeCount < PSYCHOLOGY_INSIGHTS_REQUIRED_COUNT ? (
            <p
              className="mb-2 text-[10px] tabular-nums text-gray-500"
              data-testid="dashboard.psychologyInsights.progress"
            >
              Full analytics depth: check-in days{" "}
              {displayCheckInDayCountForGate(unlock)}/{PSYCHOLOGY_INSIGHTS_REQUIRED_COUNT}
              {" · "}
              trades {displayTradeCountForGate(unlock)}/{PSYCHOLOGY_INSIGHTS_REQUIRED_COUNT}
            </p>
          ) : null}
          <PsychologyInsightCardList
            cards={displayCards}
            onOpenAnalytics={openAnalytics}
          />
        </>
      )}
    </section>
  )
}

function PsychologyInsightCardList({
  cards,
  onOpenAnalytics,
}: {
  cards: PsychologyInsightCard[]
  onOpenAnalytics: (sectionId: string | null) => void
}) {
  const [expanded, setExpanded] = useState(false)
  const visible =
    cards.length > INSIGHT_PREVIEW_COUNT && !expanded
      ? cards.slice(0, INSIGHT_PREVIEW_COUNT)
      : cards
  const canExpand = cards.length > INSIGHT_PREVIEW_COUNT

  return (
    <div className="space-y-2">
      {visible.map((card) => (
        <PsychologyInsightCardRow
          key={card.id}
          card={card}
          onSelect={() =>
            onOpenAnalytics(psychologySectionIdForCategory(card.category))
          }
        />
      ))}
      {canExpand ? (
        <button
          type="button"
          className="w-full py-1 text-xs font-semibold text-blue-400"
          onClick={() => setExpanded((value) => !value)}
        >
          {expanded
            ? "Show fewer insights"
            : `Show ${cards.length - INSIGHT_PREVIEW_COUNT} more insights`}
        </button>
      ) : null}
    </div>
  )
}
