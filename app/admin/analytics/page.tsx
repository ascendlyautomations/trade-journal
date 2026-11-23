"use client"

import Link from "next/link"
import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import {
  DAU_DEFINITION,
  type AdminAnalyticsBundle,
  type DailyCountPoint,
  fetchAdminAnalyticsBundle,
} from "@/lib/adminAnalytics"
import {
  LEGACY_ACTIVITY_DAU_DEFINITION,
  PRODUCT_DAU_DEFINITION,
  type AdminProductAnalyticsBundle,
  type ProductDailyCountPoint,
  fetchAdminProductAnalyticsBundle,
  formatMetricUnavailable,
  productActiveChartData,
  retentionRateLabel,
  formatPercent,
} from "@/lib/adminProductAnalytics"
import {
  HISTORICAL_ENGAGEMENT_DEFINITION,
  HISTORICAL_EXECUTION_DATE_DEFINITION,
  fetchAdminHistoricalEngagementBundle,
  historicalRetentionRateLabel,
  type AdminHistoricalEngagementBundle,
} from "@/lib/adminHistoricalEngagement"
import {
  loadHistoricalEngagementQuery,
  saveHistoricalEngagementQuery,
  validateHistoricalEngagementQuery,
  type HistoricalEngagementQuery,
} from "@/lib/adminHistoricalEngagementFilters"
import { HistoricalEngagementFiltersBar } from "@/components/admin/HistoricalEngagementFiltersBar"
import {
  fetchAdminLifecycleAnalyticsBundle,
  retentionRateLabel as lifecycleRetentionLabel,
  type AdminLifecycleAnalyticsBundle,
} from "@/lib/adminLifecycleAnalytics"
import {
  loadLifecycleAnalyticsQuery,
  saveLifecycleAnalyticsQuery,
  validateLifecycleAnalyticsQuery,
  type AdminLifecycleAnalyticsQuery,
} from "@/lib/adminLifecycleAnalyticsFilters"
import { LifecycleAnalyticsFiltersBar } from "@/components/admin/LifecycleAnalyticsFiltersBar"
import { FunnelStagesTable } from "@/components/admin/FunnelStagesTable"
import { getCurrentAdminCheckResult } from "@/lib/adminUsers"
import { supabase } from "@/lib/supabaseClient"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts"
import {
  chartAxisTick,
  chartCartesianGridProps,
  chartTooltipStyles,
} from "@/lib/chartTheme"

type SeriesRange = 7 | 30 | 90

function MetricCard({
  label,
  value,
  hint,
}: {
  label: string
  value: string | number
  hint?: string
}) {
  return (
    <div className="rounded-xl border border-white/10 bg-white/5 p-4 shadow-sm">
      <p className="text-xs font-medium uppercase tracking-wide text-gray-400">{label}</p>
      <p className="mt-2 text-2xl font-semibold tabular-nums text-white">{value}</p>
      {hint ? <p className="mt-1 text-xs text-gray-400">{hint}</p> : null}
    </div>
  )
}

function sortSeriesPoints(points: DailyCountPoint[]): DailyCountPoint[] {
  return [...points].sort((a, b) => String(a.day).localeCompare(String(b.day)))
}

function chartDataOrPlaceholder(points: DailyCountPoint[]): DailyCountPoint[] {
  const sorted = sortSeriesPoints(points)
  if (sorted.length) return sorted
  return [{ day: "—", count: 0 }]
}

function ProductActiveUsersChart({
  title,
  points,
  trackingStart,
}: {
  title: string
  points: ProductDailyCountPoint[]
  trackingStart: string | null
}) {
  const chartData = productActiveChartData(points)
  return (
    <div className="rounded-xl border border-white/10 bg-black/20 p-3">
      <p className="mb-2 text-sm font-medium text-gray-200">{title}</p>
      {trackingStart ? (
        <p className="mb-2 text-xs text-gray-400">
          Days before {trackingStart} UTC are not tracked (shown as gaps, not zero).
        </p>
      ) : null}
      <div className="h-56 w-full">
        {chartData.length === 0 ? (
          <p className="flex h-full items-center justify-center text-sm text-gray-400">—</p>
        ) : (
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={chartData} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
              <CartesianGrid strokeDasharray="3 3" {...chartCartesianGridProps} />
              <XAxis dataKey="day" {...chartAxisTick(11)} />
              <YAxis width={40} {...chartAxisTick(11)} allowDecimals={false} domain={[0, "auto"]} />
              <Tooltip
                {...chartTooltipStyles}
                formatter={(value) => [value, "count"]}
                labelFormatter={(label) => `Day ${label}`}
              />
              <Line
                type="monotone"
                dataKey="count"
                stroke="#60a5fa"
                strokeWidth={2}
                dot={{ r: 3 }}
                connectNulls={false}
              />
            </LineChart>
          </ResponsiveContainer>
        )}
      </div>
    </div>
  )
}

function LineChartCard({
  title,
  data,
  color,
}: {
  title: string
  data: DailyCountPoint[]
  color: string
}) {
  return (
    <div className="rounded-xl border border-white/10 bg-black/20 p-3">
      <p className="mb-2 text-sm font-medium text-gray-200">{title}</p>
      <div className="h-56 w-full">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={chartDataOrPlaceholder(data)} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
            <CartesianGrid strokeDasharray="3 3" {...chartCartesianGridProps} />
            <XAxis dataKey="day" {...chartAxisTick(11)} />
            <YAxis width={40} {...chartAxisTick(11)} allowDecimals={false} domain={[0, "auto"]} />
            <Tooltip
              {...chartTooltipStyles}
              formatter={(value) => [value, "count"]}
              labelFormatter={(label) => `Day ${label}`}
            />
            <Line type="monotone" dataKey="count" stroke={color} strokeWidth={2} dot={{ r: 3 }} />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </div>
  )
}

export default function AdminAnalyticsPage() {
  const router = useRouter()
  const [checking, setChecking] = useState(true)
  const [allowed, setAllowed] = useState(false)
  const [seriesDays, setSeriesDays] = useState<SeriesRange>(30)
  const [bundle, setBundle] = useState<AdminAnalyticsBundle | null>(null)
  const [productBundle, setProductBundle] = useState<AdminProductAnalyticsBundle | null>(null)
  const [historicalQuery, setHistoricalQuery] = useState<HistoricalEngagementQuery>(() =>
    loadHistoricalEngagementQuery()
  )
  const [historicalBundle, setHistoricalBundle] = useState<AdminHistoricalEngagementBundle | null>(null)
  const [historicalLoading, setHistoricalLoading] = useState(false)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [productLoadError, setProductLoadError] = useState<string | null>(null)
  const [historicalLoadError, setHistoricalLoadError] = useState<string | null>(null)
  const [lifecycleQuery, setLifecycleQuery] = useState<AdminLifecycleAnalyticsQuery>(() =>
    loadLifecycleAnalyticsQuery()
  )
  const [lifecycleBundle, setLifecycleBundle] = useState<AdminLifecycleAnalyticsBundle | null>(null)
  const [lifecycleLoading, setLifecycleLoading] = useState(false)
  const [lifecycleLoadError, setLifecycleLoadError] = useState<string | null>(null)

  const lifecycleValidation = useMemo(
    () => validateLifecycleAnalyticsQuery(lifecycleQuery),
    [lifecycleQuery]
  )

  const historicalValidation = useMemo(
    () => validateHistoricalEngagementQuery(historicalQuery),
    [historicalQuery]
  )

  const showTradingCharts =
    historicalQuery.activityFilter === "all" || historicalQuery.activityFilter === "trading"
  const showSocialCharts =
    historicalQuery.activityFilter === "all" || historicalQuery.activityFilter === "social"

  useEffect(() => {
    let cancelled = false
    void (async () => {
      const check = await getCurrentAdminCheckResult()
      if (!check.userId) {
        router.replace("/login")
        return
      }
      if (!check.isAdmin) {
        router.replace("/dashboard")
        return
      }
      if (!cancelled) {
        setAllowed(true)
        setChecking(false)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [router])

  useEffect(() => {
    if (!allowed) return
    let cancelled = false
    void (async () => {
      setLoadError(null)
      setProductLoadError(null)
      const [legacy, product] = await Promise.all([
        fetchAdminAnalyticsBundle(supabase, seriesDays),
        fetchAdminProductAnalyticsBundle(supabase, seriesDays),
      ])
      if (cancelled) return
      if (legacy.error) {
        setLoadError(toUserFacingErrorMessage(legacy.error))
        setBundle(null)
      } else {
        setBundle(legacy.data)
      }
      if (product.error) {
        setProductLoadError(toUserFacingErrorMessage(product.error))
        setProductBundle(null)
      } else {
        setProductBundle(product.data)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [allowed, seriesDays])

  useEffect(() => {
    saveHistoricalEngagementQuery(historicalQuery)
  }, [historicalQuery])

  useEffect(() => {
    saveLifecycleAnalyticsQuery(lifecycleQuery)
  }, [lifecycleQuery])

  useEffect(() => {
    if (!allowed) return
    if (!lifecycleValidation.valid) {
      setLifecycleBundle(null)
      setLifecycleLoadError(null)
      setLifecycleLoading(false)
      return
    }
    let cancelled = false
    void (async () => {
      setLifecycleLoading(true)
      setLifecycleLoadError(null)
      const result = await fetchAdminLifecycleAnalyticsBundle(supabase, lifecycleQuery)
      if (cancelled) return
      setLifecycleLoading(false)
      if (result.error) {
        setLifecycleLoadError(toUserFacingErrorMessage(result.error))
        setLifecycleBundle(null)
      } else {
        setLifecycleBundle(result.data)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [allowed, lifecycleQuery, lifecycleValidation.valid])

  useEffect(() => {
    if (!allowed) return
    if (!historicalValidation.valid) {
      setHistoricalBundle(null)
      setHistoricalLoadError(null)
      setHistoricalLoading(false)
      return
    }
    let cancelled = false
    void (async () => {
      setHistoricalLoading(true)
      setHistoricalLoadError(null)
      const historical = await fetchAdminHistoricalEngagementBundle(supabase, historicalQuery)
      if (cancelled) return
      setHistoricalLoading(false)
      if (historical.error) {
        setHistoricalLoadError(toUserFacingErrorMessage(historical.error))
        setHistoricalBundle(null)
      } else {
        setHistoricalBundle(historical.data)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [allowed, historicalQuery, historicalValidation.valid])

  const usersChartData = useMemo(
    () => (bundle ? chartDataOrPlaceholder(bundle.series.usersPerDay) : []),
    [bundle]
  )
  const tradesChartData = useMemo(
    () => (bundle ? chartDataOrPlaceholder(bundle.series.tradesPerDay) : []),
    [bundle]
  )
  const postsChartData = useMemo(
    () => (bundle ? chartDataOrPlaceholder(bundle.series.postsPerDay) : []),
    [bundle]
  )

  if (checking || !allowed) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-8 text-white">
        Checking admin access…
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-4 text-gray-100 md:p-8">
      <div className="mx-auto max-w-6xl space-y-6">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h1 className="text-2xl font-bold text-blue-300 md:text-3xl">Analytics</h1>
              <p className="mt-1 text-sm text-gray-400">
              Product active users (session/app-open rollups) vs legacy trade/post activity (UTC).
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <div className="flex rounded-lg border border-white/10 bg-black/20 p-1">
              {([7, 30, 90] as const).map((d) => (
                <button
                  key={d}
                  type="button"
                  onClick={() => setSeriesDays(d)}
                  className={`rounded-md px-3 py-1 text-sm ${
                    seriesDays === d ? "bg-white/15 text-white" : "text-gray-400 hover:text-gray-200"
                  }`}
                >
                  {d}D
                </button>
              ))}
            </div>
            <Link href="/admin" className="rounded bg-white/10 px-3 py-2 text-sm hover:bg-white/20">
              Back to Admin
            </Link>
          </div>
        </div>

        {productLoadError ? (
          <div className="rounded-xl border border-amber-500/40 bg-amber-950/30 p-4 text-sm text-amber-100">
            Product analytics unavailable. Deploy migration{" "}
            <code className="rounded bg-black/30 px-1">20261123160000_admin_product_analytics_bundle_audit_fixes.sql</code>{" "}
            after product analytics phase 1. {productLoadError}
          </div>
        ) : null}

        {productBundle ? (
          <>
            {productBundle.meta.notes.length > 0 ? (
              <section className="rounded-xl border border-blue-500/30 bg-blue-950/20 p-4 text-sm text-blue-100">
                <h2 className="font-semibold text-white">Tracking notes</h2>
                <ul className="mt-2 list-disc space-y-1 pl-5 text-gray-200">
                  {productBundle.meta.notes.map((note) => (
                    <li key={note}>{note}</li>
                  ))}
                </ul>
              </section>
            ) : null}

            <section className="space-y-3">
              <h2 className="text-lg font-semibold text-white">Product active users (tracked)</h2>
              <p className="text-sm text-gray-400">{PRODUCT_DAU_DEFINITION}</p>
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
                <MetricCard label="Total users" value={productBundle.overview.totalUsers} />
                <MetricCard label="New signups today" value={productBundle.overview.newSignupsToday} />
                <MetricCard
                  label="Product DAU"
                  value={formatMetricUnavailable(productBundle.overview.productDau)}
                  hint={PRODUCT_DAU_DEFINITION}
                />
                <MetricCard
                  label="Product WAU"
                  value={formatMetricUnavailable(productBundle.overview.productWau)}
                />
                <MetricCard
                  label="Product MAU"
                  value={formatMetricUnavailable(productBundle.overview.productMau)}
                />
                <MetricCard
                  label="DAU / MAU"
                  value={
                    productBundle.overview.dauMauRatio != null
                      ? productBundle.overview.dauMauRatio.toFixed(2)
                      : "—"
                  }
                />
              </div>
            </section>

            <section className="space-y-3">
              <h2 className="text-lg font-semibold text-white">Growth ({seriesDays}D)</h2>
              <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                <LineChartCard
                  title="Signups / day"
                  data={productBundle.growth.signupsPerDay}
                  color="#34d399"
                />
                <ProductActiveUsersChart
                  title="Product active users / day"
                  points={productBundle.growth.productActiveUsersPerDay}
                  trackingStart={productBundle.meta.productTrackingStartDate}
                />
              </div>
            </section>

            <section className="space-y-3">
              <h2 className="text-lg font-semibold text-white">Retention</h2>
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
                <MetricCard
                  label="D1 retention"
                  value={retentionRateLabel(
                    productBundle.retention.d1Rate,
                    productBundle.retention.d1MatureCohortSize,
                    productBundle.retention.insufficientData
                  )}
                  hint={`Mature cohort (≥1d): ${productBundle.retention.d1MatureCohortSize}`}
                />
                <MetricCard
                  label="D7 retention"
                  value={retentionRateLabel(
                    productBundle.retention.d7Rate,
                    productBundle.retention.d7MatureCohortSize,
                    productBundle.retention.insufficientData
                  )}
                  hint={`Mature cohort (≥7d): ${productBundle.retention.d7MatureCohortSize}`}
                />
                <MetricCard
                  label="D30 retention"
                  value={retentionRateLabel(
                    productBundle.retention.d30Rate,
                    productBundle.retention.d30MatureCohortSize,
                    productBundle.retention.insufficientData
                  )}
                  hint={`Mature cohort (≥30d): ${productBundle.retention.d30MatureCohortSize}`}
                />
              </div>
              <LineChartCard
                title="Returning users / day"
                data={productBundle.retention.returningUsersPerDay}
                color="#a78bfa"
              />
            </section>

            <section className="space-y-3">
              <h2 className="text-lg font-semibold text-white">Trading activity</h2>
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
                <MetricCard
                  label="Trades / active trader (today)"
                  value={formatMetricUnavailable(productBundle.trading.tradesPerActiveTraderLatestDay)}
                />
                <MetricCard
                  label="Manually entered trades"
                  value={productBundle.trading.importTotalsInPeriod.manualEntered}
                  hint="import_source = manual"
                />
                <MetricCard
                  label="Legacy trades (unset source)"
                  value={productBundle.trading.importTotalsInPeriod.unsetImportSource}
                  hint="Missing import_source on older rows"
                />
                <MetricCard label="CSV trades" value={productBundle.trading.importTotalsInPeriod.csv} />
                <MetricCard label="Broker trades" value={productBundle.trading.importTotalsInPeriod.broker} />
              </div>
              <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                <LineChartCard title="Trades created / day" data={productBundle.trading.tradesCreatedPerDay} color="#60a5fa" />
                <LineChartCard title="Active traders / day" data={productBundle.trading.activeTradersPerDay} color="#f472b6" />
              </div>
            </section>

            <section className="space-y-3">
              <h2 className="text-lg font-semibold text-white">Social & feature engagement</h2>
              <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                <LineChartCard title="Profile views / day" data={productBundle.social.profileViewsPerDay} color="#fbbf24" />
                <LineChartCard
                  title="Unique profile viewers / day"
                  data={productBundle.social.uniqueProfileViewersPerDay}
                  color="#f59e0b"
                />
                <LineChartCard title="Posts / day" data={productBundle.social.postsPerDay} color="#34d399" />
                <LineChartCard
                  title="Feature engagement events / day"
                  data={productBundle.social.featureEngagementPerDay}
                  color="#38bdf8"
                />
              </div>
              {productBundle.features.topFeatures.length > 0 ? (
                <div className="overflow-x-auto rounded-xl border border-white/10 bg-black/20">
                  <table className="min-w-full text-left text-sm">
                    <thead className="text-xs uppercase text-gray-400">
                      <tr>
                        <th className="px-3 py-2">Feature</th>
                        <th className="px-3 py-2">Uses</th>
                        <th className="px-3 py-2">Unique users</th>
                        <th className="px-3 py-2">Web</th>
                        <th className="px-3 py-2">iOS</th>
                      </tr>
                    </thead>
                    <tbody>
                      {productBundle.features.topFeatures.map((row) => (
                        <tr key={row.feature} className="border-t border-white/5 text-gray-200">
                          <td className="px-3 py-2 font-medium">{row.feature || "—"}</td>
                          <td className="px-3 py-2 tabular-nums">{row.useCount}</td>
                          <td className="px-3 py-2 tabular-nums">{row.uniqueUsers}</td>
                          <td className="px-3 py-2 tabular-nums">{row.webUniqueUsers}</td>
                          <td className="px-3 py-2 tabular-nums">{row.iosUniqueUsers}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              ) : null}
            </section>

            {productBundle.traxsProPreview.available ? (
              <section className="space-y-3">
                <h2 className="text-lg font-semibold text-white">TraxsPro interactive preview</h2>
                <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
                  <MetricCard label="Preview starts" value={productBundle.traxsProPreview.funnelTotals.starts} />
                  <MetricCard label="Preview exits" value={productBundle.traxsProPreview.funnelTotals.exits} />
                  <MetricCard label="Upgrade taps" value={productBundle.traxsProPreview.funnelTotals.upgradeTaps} />
                  <MetricCard
                    label="Start → upgrade"
                    value={formatPercent(productBundle.traxsProPreview.funnelTotals.startToUpgradeRate)}
                  />
                </div>
                <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
                  <LineChartCard title="Preview starts / day" data={productBundle.traxsProPreview.startsPerDay} color="#818cf8" />
                  <LineChartCard title="Preview exits / day" data={productBundle.traxsProPreview.exitsPerDay} color="#94a3b8" />
                  <LineChartCard
                    title="Upgrade taps / day"
                    data={productBundle.traxsProPreview.upgradeTapsPerDay}
                    color="#4ade80"
                  />
                </div>
              </section>
            ) : null}
          </>
        ) : !productLoadError ? (
          <p className="text-sm text-gray-400">Loading product metrics…</p>
        ) : null}

        <section className="space-y-6 border-t border-white/10 pt-8">
          <div>
            <h2 className="text-lg font-semibold text-white">User growth &amp; activation</h2>
            <p className="mt-1 max-w-3xl text-sm text-gray-400">
              Signup cohort funnel with conversion, drop-off, and median hours to each milestone (UTC).
            </p>
          </div>
          <LifecycleAnalyticsFiltersBar query={lifecycleQuery} onChange={setLifecycleQuery} />
          {lifecycleLoadError ? (
            <div className="rounded-xl border border-amber-500/40 bg-amber-950/30 p-4 text-sm text-amber-100">
              Lifecycle analytics unavailable. Deploy migrations{" "}
              <code className="rounded bg-black/30 px-1">20261123230000</code> and{" "}
              <code className="rounded bg-black/30 px-1">20261123230100_admin_lifecycle_analytics_bundle.sql</code>.{" "}
              {lifecycleLoadError}
            </div>
          ) : null}
          {lifecycleBundle ? (
            <>
              {lifecycleBundle.meta.notes.length > 0 ? (
                <ul className="list-disc space-y-1 pl-5 text-xs text-gray-400">
                  {lifecycleBundle.meta.notes.map((note) => (
                    <li key={note}>{note}</li>
                  ))}
                </ul>
              ) : null}
              <p className="text-xs text-gray-500">
                Cohort signups: {lifecycleBundle.userGrowthActivation.cohortSignups.toLocaleString()}
                {lifecycleBundle.meta.periodStart && lifecycleBundle.meta.periodEnd
                  ? ` · ${lifecycleBundle.meta.periodStart} → ${lifecycleBundle.meta.periodEnd} UTC`
                  : null}
              </p>
              <FunnelStagesTable stages={lifecycleBundle.userGrowthActivation.stages} />
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
                <MetricCard
                  label="Median hrs → onboarding"
                  value={lifecycleBundle.userGrowthActivation.medianHoursToStage.onboarding ?? "—"}
                />
                <MetricCard
                  label="Median hrs → account"
                  value={lifecycleBundle.userGrowthActivation.medianHoursToStage.firstAccount ?? "—"}
                />
                <MetricCard
                  label="Median hrs → trade"
                  value={lifecycleBundle.userGrowthActivation.medianHoursToStage.firstTrade ?? "—"}
                />
                <MetricCard
                  label="Median hrs → social"
                  value={lifecycleBundle.userGrowthActivation.medianHoursToStage.firstSocial ?? "—"}
                />
                <MetricCard
                  label="Median hrs → return"
                  value={lifecycleBundle.userGrowthActivation.medianHoursToStage.firstReturnVisit ?? "—"}
                  hint="Tracked sessions only"
                />
              </div>
            </>
          ) : lifecycleLoading && lifecycleValidation.valid ? (
            <p className="text-sm text-gray-400">Loading activation funnel…</p>
          ) : null}

          <div>
            <h2 className="text-lg font-semibold text-white">TraxsPro conversion</h2>
            <p className="mt-1 text-sm text-gray-400">
              Preview, paywall, and billing-backed subscription steps — not inferred from upgrade clicks alone.
            </p>
          </div>
          {lifecycleBundle ? (
            <>
              <FunnelStagesTable stages={lifecycleBundle.traxsProConversion.stages} />
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
                <MetricCard
                  label="Paywall views (web)"
                  value={lifecycleBundle.traxsProConversion.platform.paywallViews.web}
                />
                <MetricCard
                  label="Paywall views (iOS)"
                  value={lifecycleBundle.traxsProConversion.platform.paywallViews.ios}
                />
                <MetricCard
                  label="Upgrade clicks (web)"
                  value={lifecycleBundle.traxsProConversion.platform.upgradeClicks.web}
                />
                <MetricCard
                  label="Upgrade clicks (iOS)"
                  value={lifecycleBundle.traxsProConversion.platform.upgradeClicks.ios}
                />
              </div>
            </>
          ) : null}

          <div>
            <h2 className="text-lg font-semibold text-white">Retention &amp; churn</h2>
            <p className="mt-1 text-sm text-gray-400">
              Session retention from product rollups. Content retention stays under Historical Engagement; paid churn uses billing records.
            </p>
          </div>
          {lifecycleBundle ? (
            <>
              <span className="text-xs text-gray-500">{lifecycleBundle.retentionChurn.sessionRetention.definition}</span>
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
                <MetricCard
                  label="Session D1"
                  value={lifecycleRetentionLabel(
                    lifecycleBundle.retentionChurn.sessionRetention.d1Rate,
                    lifecycleBundle.retentionChurn.sessionRetention.d1MatureCohortSize,
                    lifecycleBundle.retentionChurn.sessionRetention.insufficientData
                  )}
                />
                <MetricCard
                  label="Session D7"
                  value={lifecycleRetentionLabel(
                    lifecycleBundle.retentionChurn.sessionRetention.d7Rate,
                    lifecycleBundle.retentionChurn.sessionRetention.d7MatureCohortSize,
                    lifecycleBundle.retentionChurn.sessionRetention.insufficientData
                  )}
                />
                <MetricCard
                  label="Session D30"
                  value={lifecycleRetentionLabel(
                    lifecycleBundle.retentionChurn.sessionRetention.d30Rate,
                    lifecycleBundle.retentionChurn.sessionRetention.d30MatureCohortSize,
                    lifecycleBundle.retentionChurn.sessionRetention.insufficientData
                  )}
                />
              </div>
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
                <MetricCard
                  label="Inactive 7d"
                  value={lifecycleBundle.retentionChurn.inactiveUsers.inactive7Days}
                  hint={`As of ${lifecycleBundle.retentionChurn.inactiveUsers.asOfDate} UTC`}
                />
                <MetricCard
                  label="Inactive 14d"
                  value={lifecycleBundle.retentionChurn.inactiveUsers.inactive14Days}
                />
                <MetricCard
                  label="Inactive 30d"
                  value={lifecycleBundle.retentionChurn.inactiveUsers.inactive30Days}
                />
                <MetricCard
                  label="Pro subscribers (now)"
                  value={lifecycleBundle.retentionChurn.subscriberChurn.activeSubscribersAtPeriodEnd}
                  hint={lifecycleBundle.retentionChurn.subscriberChurn.definition}
                />
              </div>
              <p className="text-xs text-gray-500">
                Cancellations in period: {lifecycleBundle.traxsProConversion.billingInPeriod.cancellations} · Apple
                expired: {lifecycleBundle.traxsProConversion.billingInPeriod.appleExpired} · New Apple subs:{" "}
                {lifecycleBundle.traxsProConversion.billingInPeriod.newSubscriptions}
              </p>
              <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                <LineChartCard
                  title="Weekly returning users"
                  data={lifecycleBundle.retentionChurn.weeklyReturningUsers}
                  color="#a78bfa"
                />
                <LineChartCard
                  title="New session users / day"
                  data={lifecycleBundle.retentionChurn.newVsReturningUsersPerDay.map((d) => ({
                    day: d.day,
                    count: d.newUsers,
                  }))}
                  color="#34d399"
                />
                <LineChartCard
                  title="Returning session users / day"
                  data={lifecycleBundle.retentionChurn.newVsReturningUsersPerDay.map((d) => ({
                    day: d.day,
                    count: d.returningUsers,
                  }))}
                  color="#60a5fa"
                />
              </div>
            </>
          ) : null}
        </section>

        <section className="space-y-4 border-t border-white/10 pt-8">
          <div>
            <h2 className="text-lg font-semibold text-white">Historical engagement</h2>
            <p className="mt-1 max-w-3xl text-sm text-gray-400">{HISTORICAL_ENGAGEMENT_DEFINITION}</p>
            <p className="mt-1 text-xs text-amber-200/90">
              Content activity only — not product sessions. No historical web/iOS platform data.
            </p>
          </div>

          <HistoricalEngagementFiltersBar
            query={historicalQuery}
            onChange={setHistoricalQuery}
          />

          {historicalLoadError ? (
            <div className="rounded-xl border border-amber-500/40 bg-amber-950/30 p-4 text-sm text-amber-100">
              Historical engagement unavailable. Deploy migrations{" "}
              <code className="rounded bg-black/30 px-1">20261123180000</code> and{" "}
              <code className="rounded bg-black/30 px-1">20261123210000_admin_historical_engagement_bundle_filters.sql</code>.{" "}
              {historicalLoadError}
            </div>
          ) : null}

          {!historicalValidation.valid && historicalQuery.preset === "custom" ? (
            <p className="text-sm text-gray-400">Select a valid custom UTC date range to load metrics.</p>
          ) : null}

          {historicalBundle ? (
            <>
              {historicalBundle.meta.notes.length > 0 ? (
                <ul className="list-disc space-y-1 pl-5 text-xs text-gray-400">
                  {historicalBundle.meta.notes.map((note) => (
                    <li key={note}>{note}</li>
                  ))}
                </ul>
              ) : null}

              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
                <MetricCard label="Engaged DAU" value={historicalBundle.overview.engagedDau} hint={HISTORICAL_ENGAGEMENT_DEFINITION} />
                <MetricCard label="Engaged WAU" value={historicalBundle.overview.engagedWau} />
                <MetricCard label="Engaged MAU" value={historicalBundle.overview.engagedMau} />
                <MetricCard
                  label="Active traders (period end)"
                  value={historicalBundle.overview.activeTradersDau}
                  hint="Organic trades logged on last UTC day of range"
                />
                <MetricCard
                  label="Active creators (period end)"
                  value={historicalBundle.overview.activeCreatorsDau}
                />
                <MetricCard
                  label="Messengers (period end)"
                  value={historicalBundle.overview.activeMessengersDau}
                />
                <MetricCard label="Signups in period" value={historicalBundle.overview.newSignupsInPeriod} />
                <MetricCard label="Accounts created" value={historicalBundle.overview.accountsCreatedInPeriod} />
              </div>

              <section className="space-y-3">
                <h3 className="text-base font-semibold text-white">Historical content retention</h3>
                <p className="text-xs text-gray-400">{historicalBundle.retention.definition}</p>
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
                  <MetricCard
                    label="D1 content retention"
                    value={historicalRetentionRateLabel(
                      historicalBundle.retention.d1Rate,
                      historicalBundle.retention.d1MatureCohortSize,
                      historicalBundle.retention.insufficientData
                    )}
                    hint={`Mature cohort: ${historicalBundle.retention.d1MatureCohortSize}`}
                  />
                  <MetricCard
                    label="D7 content retention"
                    value={historicalRetentionRateLabel(
                      historicalBundle.retention.d7Rate,
                      historicalBundle.retention.d7MatureCohortSize,
                      historicalBundle.retention.insufficientData
                    )}
                    hint={`Mature cohort: ${historicalBundle.retention.d7MatureCohortSize}`}
                  />
                  <MetricCard
                    label="D30 content retention"
                    value={historicalRetentionRateLabel(
                      historicalBundle.retention.d30Rate,
                      historicalBundle.retention.d30MatureCohortSize,
                      historicalBundle.retention.insufficientData
                    )}
                    hint={`Mature cohort: ${historicalBundle.retention.d30MatureCohortSize} · signups tracked: ${historicalBundle.retention.cohortSignupsTotal}`}
                  />
                </div>
              </section>

              {showTradingCharts ? (
                <section className="space-y-3">
                  <h3 className="text-base font-semibold text-white">
                    Trade import quality ({historicalBundle.seriesDays} UTC days)
                  </h3>
                  <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
                    <MetricCard label="Manual entered" value={historicalBundle.trading.importQuality.manualEntered} />
                    <MetricCard label="Unset import source" value={historicalBundle.trading.importQuality.unsetImportSource} />
                    <MetricCard label="Bulk initial import" value={historicalBundle.trading.importQuality.bulkInitialImportRows} />
                    <MetricCard label="Organic trades logged" value={historicalBundle.trading.importQuality.organicTradesLogged} />
                    <MetricCard
                      label="Execution before logged"
                      value={historicalBundle.trading.importQuality.tradeDateBeforeCreatedDayRows}
                    />
                    <MetricCard label="Missing trade_date" value={historicalBundle.trading.importQuality.nullTradeDateRows} />
                  </div>
                </section>
              ) : null}

              <section className="space-y-4">
                <h3 className="text-base font-semibold text-white">
                  Activity charts
                  {historicalBundle.meta.periodStart && historicalBundle.meta.periodEnd
                    ? ` (${historicalBundle.meta.periodStart} → ${historicalBundle.meta.periodEnd} UTC)`
                    : ` (${historicalBundle.seriesDays}D)`}
                </h3>
                <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                  <LineChartCard title="Engaged users / day" data={historicalBundle.engagement.engagedUsersPerDay} color="#a78bfa" />
                  <LineChartCard
                    title="Returning engaged users / day"
                    data={historicalBundle.engagement.returningEngagedUsersPerDay}
                    color="#c4b5fd"
                  />
                  {showSocialCharts ? (
                    <LineChartCard
                      title="Returning creators / day"
                      data={historicalBundle.engagement.returningCreatorsPerDay}
                      color="#f472b6"
                    />
                  ) : null}
                  {showTradingCharts ? (
                    <>
                      <LineChartCard title="Active traders / day" data={historicalBundle.trading.activeTradersPerDay} color="#60a5fa" />
                      <LineChartCard
                        title="Returning traders / day"
                        data={historicalBundle.trading.returningTradersPerDay}
                        color="#38bdf8"
                      />
                      <LineChartCard title="Trades logged / day (all)" data={historicalBundle.trading.tradesLoggedPerDay} color="#3b82f6" />
                      <LineChartCard
                        title="Organic trades logged / day"
                        data={historicalBundle.trading.organicTradesLoggedPerDay}
                        color="#2563eb"
                      />
                      <LineChartCard
                        title="Bulk import trades / day"
                        data={historicalBundle.trading.bulkImportTradesPerDay}
                        color="#64748b"
                      />
                      <LineChartCard
                        title="Trades by execution date / day"
                        data={historicalBundle.trading.tradesByExecutionDatePerDay}
                        color="#475569"
                      />
                    </>
                  ) : null}
                  <LineChartCard title="Signups / day" data={historicalBundle.growth.signupsPerDay} color="#34d399" />
                  <LineChartCard
                    title="Trading accounts created / day"
                    data={historicalBundle.growth.accountsCreatedPerDay}
                    color="#10b981"
                  />
                  {showSocialCharts ? (
                    <>
                      <LineChartCard title="Posts / day" data={historicalBundle.social.postsPerDay} color="#fbbf24" />
                      <LineChartCard title="Profile posts / day" data={historicalBundle.social.profilePostsPerDay} color="#f59e0b" />
                      <LineChartCard title="Reels / day" data={historicalBundle.social.reelsPerDay} color="#fb923c" />
                      <LineChartCard title="Comments / day" data={historicalBundle.social.commentsPerDay} color="#fcd34d" />
                      <LineChartCard title="Likes / day" data={historicalBundle.social.likesPerDay} color="#fde047" />
                      <LineChartCard title="Follows / day" data={historicalBundle.social.followsPerDay} color="#4ade80" />
                      <LineChartCard title="Messages sent / day" data={historicalBundle.social.messagesPerDay} color="#22d3ee" />
                      <LineChartCard
                        title="Active creators / day"
                        data={historicalBundle.social.activeCreatorsPerDay}
                        color="#e879f9"
                      />
                      <LineChartCard
                        title="Active messengers / day"
                        data={historicalBundle.social.activeMessengersPerDay}
                        color="#2dd4bf"
                      />
                    </>
                  ) : null}
                </div>
                {showTradingCharts ? (
                  <p className="text-xs text-gray-500">{HISTORICAL_EXECUTION_DATE_DEFINITION}</p>
                ) : null}
              </section>
            </>
          ) : historicalLoading && historicalValidation.valid ? (
            <p className="text-sm text-gray-400">Loading historical engagement…</p>
          ) : null}
        </section>

        <section className="border-t border-white/10 pt-6">
          <h2 className="text-lg font-semibold text-white">Legacy activity metrics</h2>
          <p className="mt-1 text-xs text-gray-400">{LEGACY_ACTIVITY_DAU_DEFINITION}</p>
        </section>

        {loadError ? (
          <div className="rounded-xl border border-red-500/40 bg-red-950/40 p-4 text-sm text-red-100">
            Could not load legacy analytics. {loadError}
          </div>
        ) : null}

        {bundle ? (
          <>
            <section className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <MetricCard label="Total users" value={bundle.totalUsers} />
              <MetricCard label="New users today" value={bundle.newUsersToday} />
              <MetricCard label="New users this week" value={bundle.newUsersWeek} hint="UTC week" />
              <MetricCard
                label="Daily active users (legacy)"
                value={bundle.dailyActiveUsers}
                hint="Rolling 24h trade/post activity"
              />
              <MetricCard label="Weekly active users (legacy)" value={bundle.weeklyActiveUsers} />
              <MetricCard label="Trades logged today" value={bundle.tradesToday} />
              <MetricCard label="Trades logged this week" value={bundle.tradesWeek} />
              <MetricCard label="Posts created today" value={bundle.postsToday} />
              <MetricCard label="Posts created this week" value={bundle.postsWeek} />
              <MetricCard label="Total trades" value={bundle.totalTrades} />
              <MetricCard label="Total posts" value={bundle.totalPosts} />
              <MetricCard label="Total feedback" value={bundle.totalFeedback} />
              <MetricCard label="Total support tickets" value={bundle.totalSupport} />
              <MetricCard label="Open support tickets" value={bundle.openSupport} />
              <MetricCard label="Open feedback items" value={bundle.openFeedback} />
              <MetricCard label="Banned users" value={bundle.bannedUsers} />
            </section>

            <section className="rounded-xl border border-white/10 bg-white/5 p-4 md:p-5">
              <h2 className="text-lg font-semibold text-white">Legacy DAU / WAU (not product active users)</h2>
              <p className="mt-2 text-sm text-gray-300">{DAU_DEFINITION}</p>
            </section>

            <section className="space-y-4">
              <h2 className="text-lg font-semibold text-white">Legacy daily trends ({bundle.seriesDays} days)</h2>
              <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
                <LineChartCard title="New users / day" data={usersChartData} color="#34d399" />
                <LineChartCard title="Trades / day" data={tradesChartData} color="#60a5fa" />
                <LineChartCard title="Posts / day" data={postsChartData} color="#fbbf24" />
              </div>
            </section>
          </>
        ) : !loadError ? (
          <p className="text-sm text-gray-400">Loading legacy metrics…</p>
        ) : null}
      </div>
    </div>
  )
}