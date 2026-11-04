"use client"

import "@/app/(app)/dashboard/dashboardCanvas.css"
import type { ReactNode } from "react"
import Image from "next/image"
import Calendar from "@/app/components/Calendar"
import DashboardEquityCurve from "@/app/components/dashboard/DashboardEquityCurve"
import DashboardPropFirmDetails from "@/app/components/dashboard/DashboardPropFirmDetails"
import ExploreTopPerformersSection from "@/app/components/explore/ExploreTopPerformersSection"
import LandingExploreLink from "@/app/components/landing/v2/LandingExploreLink"
import ReelThumbnailPreview from "@/app/components/ReelThumbnailPreview"
import FeedPostCard from "@/app/components/feed/FeedPostCard"
import MobileWebTradeJournalCard from "@/app/components/mobile/trades/MobileWebTradeJournalCard"
import { getMarketingDashboardData } from "@/app/components/marketing-ads/marketingDemoData"
import { DEMO_USER_ID } from "@/lib/demo/constants"
import {
  DEMO_FEED_COMMENTS,
  DEMO_FEED_LIKES,
  fetchDemoFeedBatch,
} from "@/lib/demo/demoFeed"
import { getDemoPropfirmAccounts, getDemoPropfirmTrades } from "@/lib/demo/demoPropfirm"
import { formatCurrency } from "@/lib/formatCurrency"
import { formatDecimal, formatRR } from "@/lib/formatDisplay"
import {
  getLandingDemoTrades,
  getMarketingJournalFeedPost,
  getMarketingJournalShowcaseReel,
  getMarketingJournalShowcaseTrades,
  getLandingDemoWeeklyPerformers,
} from "./landingProductDemo"
import LandingDemoDataBadge from "./LandingDemoDataBadge"
import LandingHeroDashboardPicture from "./LandingHeroDashboardPicture"

const noop = () => {}
const asyncNoop = async () => false

export type MarketingPreviewVariant = "default" | "clean"

function MarketingFrame({
  label,
  children,
  className = "",
  embed = "",
  variant = "default",
}: {
  label?: string
  children: ReactNode
  className?: string
  embed?: string
  variant?: MarketingPreviewVariant
}) {
  const clean = variant === "clean"

  return (
    <div
      className={`tt-preview-shell ${clean ? "tt-preview-shell--clean" : ""} ${className}`.trim()}
    >
      {!clean && label ? (
        <div className="tt-preview-shell-head">
          <span className="tt-preview-shell-label">{label}</span>
          <LandingDemoDataBadge />
        </div>
      ) : null}
      <div
        className={`tt-marketing-authentic ${clean ? "tt-marketing-authentic--clean" : ""} ${embed}`.trim()}
      >
        {children}
      </div>
    </div>
  )
}

function DashboardStatCard({
  title,
  value,
  positive,
}: {
  title: string
  value: string
  positive?: boolean
}) {
  let color = "text-white"
  if (positive === true) color = "text-green-400"
  if (positive === false) color = "text-red-400"

  return (
    <div className="flex min-h-[72px] flex-col items-center justify-center rounded-xl border border-white/10 bg-white/10 p-3 text-center backdrop-blur-md md:min-h-[80px]">
      <p className="mb-0.5 text-[11px] text-gray-300 md:text-sm">{title}</p>
      <span
        className={`block text-base font-semibold leading-tight tabular-nums md:text-lg ${color}`}
      >
        {value}
      </span>
    </div>
  )
}

function AuthenticDashboardEquity({
  variant,
  stats,
}: {
  variant: "hero" | "desktop" | "mobile"
  stats: ReturnType<typeof getMarketingDashboardData>["stats"]
}) {
  return (
    <div
      className={`overflow-hidden rounded-xl tt-embed-equity tt-embed-equity--${variant} [&_.hidden]:!block`}
    >
      <DashboardEquityCurve
        data={stats.equityCurve}
        variant={variant}
        isPro
        profitFactor={stats.profitFactor}
        currentStreak={stats.currentStreak}
        avgDay={stats.avgDay}
        consistency={stats.consistency}
        totalTrades={stats.totalTrades}
      />
    </div>
  )
}

function marketingPerformanceMetrics() {
  const { stats } = getMarketingDashboardData()
  const metrics: {
    label: string
    value: string
    positive?: boolean
  }[] = [
    {
      label: "Net P/L",
      value: formatCurrency(stats.totalPnL),
      positive: stats.totalPnL >= 0,
    },
    { label: "Win rate", value: `${stats.winRate.toFixed(1)}%` },
    { label: "Profit factor", value: formatDecimal(stats.profitFactor) },
    { label: "Avg R:R", value: formatRR(stats.avgRR) },
  ]
  return metrics
}

/** Key metrics grid — no equity curve (hero already shows dashboard). */
export function ShowcasePerformanceMetrics({ showKicker = true }: { showKicker?: boolean }) {
  const metrics = marketingPerformanceMetrics()

  return (
    <div className="tt-analytics-showcase tt-analytics-showcase--metrics">
      {showKicker ? (
        <p className="tt-analytics-showcase-kicker">From journaled trades</p>
      ) : null}
      <ul className="tt-analytics-showcase-metrics">
        {metrics.map((m) => (
          <li key={m.label} className="tt-analytics-showcase-metric">
            <span className="tt-analytics-showcase-metric-label">{m.label}</span>
            <span
              className={`tt-analytics-showcase-metric-value ${
                m.positive === true
                  ? "tt-analytics-showcase-metric-value--pos"
                  : m.positive === false
                    ? "tt-analytics-showcase-metric-value--neg"
                    : ""
              }`}
            >
              {m.value}
            </span>
          </li>
        ))}
      </ul>
    </div>
  )
}

/** Focused marketing analytics — key metrics + compact equity curve (demo data). */
export function ShowcaseAnalytics() {
  const { stats } = getMarketingDashboardData()
  const metrics = marketingPerformanceMetrics()

  return (
    <div className="tt-analytics-showcase">
      <ul className="tt-analytics-showcase-metrics">
        {metrics.map((m) => (
          <li key={m.label} className="tt-analytics-showcase-metric">
            <span className="tt-analytics-showcase-metric-label">{m.label}</span>
            <span
              className={`tt-analytics-showcase-metric-value ${
                m.positive === true
                  ? "tt-analytics-showcase-metric-value--pos"
                  : m.positive === false
                    ? "tt-analytics-showcase-metric-value--neg"
                    : ""
              }`}
            >
              {m.value}
            </span>
          </li>
        ))}
      </ul>
      <div className="tt-analytics-showcase-chart tt-embed-equity tt-embed-equity--showcase">
        <AuthenticDashboardEquity variant="desktop" stats={stats} />
      </div>
    </div>
  )
}

export function CompactAnalytics({
  density = "default",
}: {
  density?: "hero" | "thumb" | "default" | "mobile" | "showcase"
}) {
  const { stats } = getMarketingDashboardData()
  const isHero = density === "hero"
  const isThumb = density === "thumb"
  const isMobile = density === "mobile"
  const embedClass = [
    "tt-embed-dashboard",
    isHero || isThumb ? "tt-embed-dashboard--hero" : "",
    isThumb ? "tt-embed-dashboard--thumb" : "",
  ]
    .filter(Boolean)
    .join(" ")

  const frame = (
    <>
      <div
        data-tt-dashboard-canvas
        className={`tt-phase3-dark space-y-3 rounded-xl border border-white/10 bg-[#0d1117] ${
          isThumb ? "p-2" : "p-3 md:p-4"
        }`}
      >
        {isHero || isThumb ? (
          <div className="grid grid-cols-3 gap-2">
            <DashboardStatCard
              title="Net P/L"
              value={formatCurrency(stats.totalPnL)}
              positive={stats.totalPnL >= 0}
            />
            <DashboardStatCard title="Win Rate" value={`${stats.winRate.toFixed(1)}%`} />
            <DashboardStatCard title="Profit Factor" value={formatDecimal(stats.profitFactor)} />
          </div>
        ) : isMobile ? (
          <div className="grid grid-cols-2 gap-2">
            <DashboardStatCard
              title="Net P/L"
              value={formatCurrency(stats.totalPnL)}
              positive={stats.totalPnL >= 0}
            />
            <DashboardStatCard title="Win Rate" value={`${stats.winRate.toFixed(1)}%`} />
          </div>
        ) : (
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
            <DashboardStatCard
              title="Net P/L"
              value={formatCurrency(stats.totalPnL)}
              positive={stats.totalPnL >= 0}
            />
            <DashboardStatCard title="Win Rate" value={`${stats.winRate.toFixed(1)}%`} />
            <DashboardStatCard title="Avg RR" value={formatRR(stats.avgRR)} />
            <DashboardStatCard title="Total Trades" value={String(stats.totalTrades)} />
            <DashboardStatCard
              title="Profit Factor"
              value={formatDecimal(stats.profitFactor)}
              positive={
                stats.profitFactor >= 1 ? true : stats.profitFactor > 0 ? false : undefined
              }
            />
            <DashboardStatCard title="Best Win Streak" value={String(stats.maxWinStreak)} />
          </div>
        )}

        <AuthenticDashboardEquity
          variant={isMobile ? "mobile" : isHero || isThumb ? "hero" : "desktop"}
          stats={stats}
        />
      </div>
    </>
  )

  if (isThumb) {
    return (
      <div className={`tt-marketing-authentic ${embedClass}`.trim()}>
        {frame}
      </div>
    )
  }

  return (
    <MarketingFrame
      label={isMobile ? "Dashboard" : "Performance"}
      embed={embedClass}
    >
      {frame}
    </MarketingFrame>
  )
}

const SAMPLE_CHECKIN = {
  sleepHours: 7.5,
  sleepQuality: 4,
  morningRating: 4,
  focusLevel: 3,
  stressLevel: 2,
} as const

function CheckInMetricBar({
  label,
  value,
  low,
  high,
}: {
  label: string
  value: number
  low: string
  high: string
}) {
  return (
    <div className="tt-marketing-checkin-metric">
      <div className="tt-marketing-checkin-metric-head">
        <span className="tt-marketing-checkin-metric-label">{label}</span>
        <span className="tt-marketing-checkin-metric-value">{value}/5</span>
      </div>
      <div className="tt-marketing-checkin-metric-track" aria-hidden>
        {[1, 2, 3, 4, 5].map((step) => (
          <span
            key={step}
            className={`tt-marketing-checkin-metric-seg ${
              step <= value ? "tt-marketing-checkin-metric-seg--on" : ""
            }`}
          />
        ))}
      </div>
      <div className="tt-marketing-checkin-metric-ends">
        <span>{low}</span>
        <span>{high}</span>
      </div>
    </div>
  )
}

function psychologyCheckInBody() {
  return (
    <div className="tt-marketing-checkin">
      <div className="tt-marketing-checkin-head">
        <span className="tt-marketing-checkin-icon" aria-hidden>
          ☀
        </span>
        <div>
          <p className="tt-marketing-checkin-title">Daily Check-In</p>
          <p className="tt-marketing-checkin-sub">Sleep, mood, focus &amp; stress</p>
        </div>
      </div>
      <div className="tt-marketing-checkin-grid">
        <CheckInMetricBar
          label="Sleep quality"
          value={SAMPLE_CHECKIN.sleepQuality}
          low="Poor"
          high="Rested"
        />
        <CheckInMetricBar
          label="Morning mood"
          value={SAMPLE_CHECKIN.morningRating}
          low="Low"
          high="Great"
        />
        <CheckInMetricBar
          label="Focus"
          value={SAMPLE_CHECKIN.focusLevel}
          low="Scattered"
          high="Locked in"
        />
        <CheckInMetricBar
          label="Stress"
          value={SAMPLE_CHECKIN.stressLevel}
          low="Calm"
          high="Elevated"
        />
      </div>
      <p className="tt-marketing-checkin-foot">
        {SAMPLE_CHECKIN.sleepHours}h sleep logged · compared with trading days on your dashboard
      </p>
    </div>
  )
}

/** Read-only daily check-in UI — matches product fields, sample values only. */
export function CompactPsychologyCheckIn({
  variant = "default",
}: {
  variant?: MarketingPreviewVariant
}) {
  const body = psychologyCheckInBody()

  if (variant === "clean") {
    return (
      <MarketingFrame variant="clean" embed="tt-embed-psychology">
        {body}
      </MarketingFrame>
    )
  }

  return (
    <MarketingFrame label="Daily check-in" embed="tt-embed-psychology">
      {body}
    </MarketingFrame>
  )
}

function compactJournalInner(
  limit: number,
  options?: { showcase?: boolean; marketingEntryExitTimes?: boolean }
) {
  const trades = options?.showcase
    ? getMarketingJournalShowcaseTrades()
    : getLandingDemoTrades().slice(0, limit)
  return (
    <div className="space-y-2">
      {trades.map((trade) => (
        <MobileWebTradeJournalCard
          key={String(trade.id)}
          trade={trade}
          marketingEntryExitTimes={options?.marketingEntryExitTimes}
          onOpen={noop}
          onEdit={noop}
          onDelete={noop}
          onSendClick={noop}
          onImageClick={noop}
        />
      ))}
    </div>
  )
}

export function CompactJournal({
  limit = 2,
  variant = "default",
  bare = false,
  showcase = false,
  marketingEntryExitTimes = false,
}: {
  limit?: number
  variant?: MarketingPreviewVariant
  bare?: boolean
  showcase?: boolean
  marketingEntryExitTimes?: boolean
}) {
  const inner = compactJournalInner(limit, { showcase, marketingEntryExitTimes })
  if (bare) {
    return <div className="tt-marketing-authentic tt-embed-journal">{inner}</div>
  }

  return (
    <MarketingFrame label="Trade journal" embed="tt-embed-journal" variant={variant}>
      {inner}
    </MarketingFrame>
  )
}

export function CompactCalendar({ variant = "default" }: { variant?: MarketingPreviewVariant }) {
  const trades = getLandingDemoTrades()

  return (
    <MarketingFrame label="Trading calendar" embed="tt-embed-calendar" variant={variant}>
      <Calendar trades={trades} showControls={false} showAccountFilter={false} />
    </MarketingFrame>
  )
}

const DEMO_FEED_OPTS = {
  scope: "global" as const,
  userId: DEMO_USER_ID,
  followingIds: [] as string[],
  page: 0,
  pageSize: 1,
}

function demoFeedPost(kind: "trade" | "profile" | "achievement") {
  return fetchDemoFeedBatch({ ...DEMO_FEED_OPTS, kind }).items[0] ?? null
}

function demoLikeMeta(postId: string) {
  return DEMO_FEED_LIKES[postId] ?? { count: 0, liked: false }
}

function compactFeedPostInner(options?: { journalShowcase?: boolean }) {
  const tradePost = options?.journalShowcase
    ? getMarketingJournalFeedPost()
    : demoFeedPost("trade")
  if (!tradePost) return null
  const tradeId = String(tradePost.id)

  return (
    <div className="tt-phase1-dark max-w-md mx-auto w-full">
      <FeedPostCard
        post={tradePost}
        user={{ id: DEMO_USER_ID }}
        likeMeta={demoLikeMeta(tradeId)}
        comments={DEMO_FEED_COMMENTS[tradeId] ?? []}
        commentSubmitting={false}
        preview
        hideAttachedReelPreview={options?.journalShowcase === true}
        onSelectPost={noop}
        onOpenComments={noop}
        onToggleLike={noop}
        onSubmitComment={asyncNoop}
        onSharePost={noop}
      />
    </div>
  )
}

export function CompactFeedPost({
  variant = "default",
  bare = false,
}: {
  variant?: MarketingPreviewVariant
  bare?: boolean
}) {
  const inner = compactFeedPostInner()
  if (!inner) return null

  if (bare) {
    return <div className="tt-marketing-authentic tt-embed-feed">{inner}</div>
  }

  return (
    <MarketingFrame label="Social Feed" embed="tt-embed-feed" variant={variant}>
      {inner}
    </MarketingFrame>
  )
}

/** Hero marketing: one journal entry linked visually to its Feed share. */
export function JournalFeedFlowShowcase() {
  const feed = compactFeedPostInner({ journalShowcase: true })
  const showcaseReel = getMarketingJournalShowcaseReel()

  return (
    <div className="tt-journal-feed-flow">
      <div className="tt-journal-feed-flow-pane tt-journal-feed-flow-pane--journal">
        <p className="tt-journal-feed-flow-pane-label">
          <span className="tt-journal-feed-flow-tag">In your journal</span>
          <LandingExploreLink
            destination="journal"
            className="tt-explore-link--pane"
          />
        </p>
        <CompactJournal
          limit={1}
          bare
          showcase
          marketingEntryExitTimes
        />
        <div className="tt-journal-feed-flow-trade-plus-video" aria-hidden>
          <span className="tt-journal-feed-flow-plus">+</span>
          <ReelThumbnailPreview
            reel={showcaseReel}
            maxWidthClass="max-w-[108px]"
            className="tt-journal-feed-flow-clip-thumb mx-0"
          />
        </div>
      </div>

      <div className="tt-journal-feed-flow-bridge" aria-hidden>
        <div className="tt-journal-feed-flow-bridge-track">
          <span className="tt-journal-feed-flow-bridge-dot tt-journal-feed-flow-bridge-dot--a" />
          <span className="tt-journal-feed-flow-bridge-line" />
          <span className="tt-journal-feed-flow-bridge-pill">Share</span>
          <span className="tt-journal-feed-flow-bridge-line" />
          <span className="tt-journal-feed-flow-bridge-dot tt-journal-feed-flow-bridge-dot--b" />
        </div>
      </div>

      <div className="tt-journal-feed-flow-pane tt-journal-feed-flow-pane--feed">
        <p className="tt-journal-feed-flow-pane-label">
          <span className="tt-journal-feed-flow-tag">On the Feed</span>
          <LandingExploreLink destination="feed" className="tt-explore-link--pane" />
        </p>
        {feed ? (
          <div className="tt-marketing-authentic tt-embed-feed">{feed}</div>
        ) : (
          <p className="tt-journal-feed-flow-fallback">Sample Feed post</p>
        )}
      </div>
    </div>
  )
}

/** Performance metrics + daily check-in — paired panels for marketing. */
export function InsightsDualShowcase() {
  return (
    <div className="tt-insights-dual">
      <section className="tt-insights-panel tt-insights-panel--metrics" aria-label="Performance analytics">
        <p className="tt-insights-panel-label">
          <span className="tt-insights-panel-tag">Performance analytics</span>
          <LandingExploreLink
            destination="analytics"
            className="tt-explore-link--pane"
          />
        </p>
        <ShowcasePerformanceMetrics showKicker={false} />
      </section>
      <section className="tt-insights-panel tt-insights-panel--psych" aria-label="Daily check-in">
        <p className="tt-insights-panel-label">
          <span className="tt-insights-panel-tag">Daily check-in</span>
          <LandingExploreLink
            destination="psychology"
            className="tt-explore-link--pane"
          />
        </p>
        {psychologyCheckInBody()}
      </section>
    </div>
  )
}

export function CompactPropFirm({ variant = "default" }: { variant?: MarketingPreviewVariant }) {
  const account = getDemoPropfirmAccounts()[0]
  if (!account) return null
  const trades = getDemoPropfirmTrades([String(account.id)])

  return (
    <MarketingFrame label="Prop Firm Mode" embed="tt-embed-propfirm" variant={variant}>
      <DashboardPropFirmDetails
        account={account}
        trades={trades}
        userId={null}
      />
    </MarketingFrame>
  )
}

export function CompactLeaderboard({
  variant = "default",
}: {
  variant?: MarketingPreviewVariant
}) {
  const payload = getLandingDemoWeeklyPerformers()

  return (
    <MarketingFrame label="Weekly leaderboard" embed="tt-embed-leaderboard" variant={variant}>
      <ExploreTopPerformersSection
        performers={payload.performers}
        periodTitle={payload.periodTitle}
        periodSubtitle={payload.periodSubtitle}
        hasLeaderboardPeriod={payload.period != null}
        showSectionHeader={false}
        loading={false}
        error={null}
        onRetry={noop}
      />
    </MarketingFrame>
  )
}

export default function LandingHeroShowcase() {
  return (
    <div aria-label="TradeTraxs dashboard preview">
      <LandingHeroDashboardPicture />
    </div>
  )
}

function IosMarketingPhoneScreenshot({
  src,
  alt,
  caption,
}: {
  src: string
  alt: string
  caption: string
}) {
  return (
    <figure className="tt-ios-screenshot-item">
      <figcaption className="tt-ios-screenshot-caption tt-ios-screenshot-caption--above">
        {caption}
      </figcaption>
      <div className="tt-ios-product-frame tt-ios-product-frame--photo pointer-events-none select-none">
        <div className="tt-ios-product-notch" aria-hidden />
        <div className="tt-ios-product-screen tt-ios-product-screen--photo">
          <Image src={src} alt={alt} width={390} height={844} className="h-auto w-full" priority={false} />
        </div>
      </div>
    </figure>
  )
}

/** Native iOS — real App Store screenshots from the shipped app. */
export function LandingIosAppScreenshot({ className = "" }: { className?: string }) {
  return (
    <div
      className={`tt-ios-screenshots pointer-events-none select-none ${className}`.trim()}
      aria-label="TradeTraxs native iOS app screens"
    >
      <IosMarketingPhoneScreenshot
        src="/marketing/ios-trades-screen.png"
        alt="TradeTraxs iOS app showing the trades list in light mode"
        caption="Light mode"
      />
      <IosMarketingPhoneScreenshot
        src="/marketing/ios-feed-clips-screen.jpg"
        alt="TradeTraxs iOS app showing Feed clips in dark mode"
        caption="Dark mode"
      />
    </div>
  )
}
