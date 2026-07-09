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
      {hint ? <p className="mt-1 text-xs text-gray-500">{hint}</p> : null}
    </div>
  )
}

/** Sort MM-DD style `day` keys using the current UTC year as anchor. */
function sortSeriesPoints(points: DailyCountPoint[]): DailyCountPoint[] {
  const y = new Date().getUTCFullYear()
  return [...points].sort((a, b) => {
    const ta = parseDayKeyUtc(a.day, y)
    const tb = parseDayKeyUtc(b.day, y)
    if (ta != null && tb != null) return ta - tb
    return String(a.day).localeCompare(String(b.day))
  })
}

function parseDayKeyUtc(day: string, year: number): number | null {
  const s = String(day).trim()
  const iso = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s)
  if (iso) {
    const t = Date.UTC(parseInt(iso[1], 10), parseInt(iso[2], 10) - 1, parseInt(iso[3], 10))
    return Number.isFinite(t) ? t : null
  }
  const m = /^(\d{2})-(\d{2})$/.exec(s)
  if (!m) return null
  const mm = parseInt(m[1], 10) - 1
  const dd = parseInt(m[2], 10)
  const t = Date.UTC(year, mm, dd)
  return Number.isFinite(t) ? t : null
}

function chartDataOrPlaceholder(points: DailyCountPoint[]): DailyCountPoint[] {
  const sorted = sortSeriesPoints(points)
  if (sorted.length) return sorted
  return [{ day: "—", count: 0 }]
}

export default function AdminAnalyticsPage() {
  const router = useRouter()
  const [checking, setChecking] = useState(true)
  const [allowed, setAllowed] = useState(false)
  const [bundle, setBundle] = useState<AdminAnalyticsBundle | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)

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
      const { data, error } = await fetchAdminAnalyticsBundle(supabase, 14)
      if (cancelled) return
      if (error) {
        setLoadError(toUserFacingErrorMessage(error))
        setBundle(null)
        return
      }
      setBundle(data)
    })()
    return () => {
      cancelled = true
    }
  }, [allowed])

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
      <>
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-8 text-white">
          Checking admin access…
        </div>
      </>
    )
  }

  return (
    <>
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-4 text-gray-100 md:p-8">
        <div className="mx-auto max-w-6xl space-y-6">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <h1 className="text-2xl font-bold text-blue-300 md:text-3xl">
                Analytics
              </h1>
              <p className="mt-1 text-sm text-gray-400">
                Aggregated product metrics (UTC). DAU/WAU count distinct users with recent activity — see note below.
              </p>
            </div>
            <Link href="/admin" className="rounded bg-white/10 px-3 py-2 text-sm hover:bg-white/20">
              Back to Admin
            </Link>
          </div>

          {loadError ? (
            <div className="rounded-xl border border-red-500/40 bg-red-950/40 p-4 text-sm text-red-100">
              Could not load analytics. Run the latest Supabase migration (admin RPCs) and ensure your admin account is
              in <code className="rounded bg-black/30 px-1">admin_users</code>. {loadError}
            </div>
          ) : null}

          {bundle ? (
            <>
              <section className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
                <MetricCard label="Total users" value={bundle.totalUsers} />
                <MetricCard label="New users today" value={bundle.newUsersToday} />
                <MetricCard label="New users this week" value={bundle.newUsersWeek} hint="UTC week: last 7 days including today" />
                <MetricCard
                  label="Daily active users"
                  value={bundle.dailyActiveUsers}
                  hint="Rolling 24h — distinct users with tracked activity"
                />
                <MetricCard label="Weekly active users" value={bundle.weeklyActiveUsers} hint="Rolling 7d — same activity sources as DAU" />
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
                <h2 className="text-lg font-semibold text-white">How DAU / WAU are calculated</h2>
                <p className="mt-2 text-sm text-gray-300">{DAU_DEFINITION}</p>
                <p className="mt-2 text-xs text-gray-500">
                  Windows: DAU uses the last 24 hours; WAU uses the last 7 days. Both are rolling windows in UTC.
                </p>
              </section>

              <section className="space-y-4">
                <h2 className="text-lg font-semibold text-white">Daily trends (UTC)</h2>
                <p className="text-xs text-gray-500">
                  Each point is <code className="rounded bg-black/40 px-1">{"{ day, count }"}</code> from{" "}
                  <code className="rounded bg-black/40 px-1">series.usersPerDay</code>,{" "}
                  <code className="rounded bg-black/40 px-1">series.tradesPerDay</code>,{" "}
                  <code className="rounded bg-black/40 px-1">series.postsPerDay</code> ({bundle.seriesDays} days).
                </p>
                <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
                  {(
                    [
                      { title: "New users / day", data: usersChartData, color: "#34d399" },
                      { title: "Trades / day", data: tradesChartData, color: "#60a5fa" },
                      { title: "Posts / day", data: postsChartData, color: "#fbbf24" },
                    ] as const
                  ).map((c) => (
                    <div key={c.title} className="rounded-xl border border-white/10 bg-black/20 p-3">
                      <p className="mb-2 text-sm font-medium text-gray-200">{c.title}</p>
                      <div className="h-56 w-full">
                        <ResponsiveContainer width="100%" height="100%">
                          <LineChart data={c.data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
                            <CartesianGrid strokeDasharray="3 3" stroke="#334155" />
                            <XAxis dataKey="day" tick={{ fill: "#94a3b8", fontSize: 11 }} />
                            <YAxis
                              width={40}
                              tick={{ fill: "#94a3b8", fontSize: 11 }}
                              allowDecimals={false}
                              domain={[0, "auto"]}
                            />
                            <Tooltip
                              contentStyle={{ background: "#0f172a", border: "1px solid #334155", borderRadius: 8 }}
                              formatter={(value: number | string) => [value, "count"]}
                              labelFormatter={(label) => `Day ${label}`}
                            />
                            <Line type="monotone" dataKey="count" stroke={c.color} strokeWidth={2} dot={{ r: 3 }} />
                          </LineChart>
                        </ResponsiveContainer>
                      </div>
                    </div>
                  ))}
                </div>
              </section>
            </>
          ) : !loadError ? (
            <p className="text-sm text-gray-400">Loading metrics…</p>
          ) : null}
        </div>
      </div>
    </>
  )
}
