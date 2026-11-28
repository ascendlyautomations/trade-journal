"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { Info } from "lucide-react"
import {
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts"
import { supabase } from "@/lib/supabaseClient"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { isBackendV2Enabled } from "@/lib/backendV2/flags"
import NativeDateInput from "@/app/components/ui/NativeDateInput"
import { fetchProfileInsightsBootstrap } from "@/lib/profileInsights/bootstrapRepository"
import type {
  ProfileInsightsBootstrapV1,
  ProfileInsightsDayRange,
  ProfileInsightsQuery,
  TopContentRow,
} from "@/lib/profileInsights/contract"

type ProfileInsightsScope =
  | { kind: "preset"; days: ProfileInsightsDayRange }
  | { kind: "custom"; startYmd: string; endYmd: string }

const PRESET_RANGES: { days: ProfileInsightsDayRange; label: string }[] = [
  { days: 7, label: "7 Days" },
  { days: 30, label: "30 Days" },
  { days: 90, label: "90 Days" },
]

function scopeToQuery(scope: ProfileInsightsScope): ProfileInsightsQuery {
  if (scope.kind === "custom") {
    return { kind: "custom", startYmd: scope.startYmd, endYmd: scope.endYmd }
  }
  return { kind: "preset", days: scope.days }
}

type TopSort = "views" | "engagement"

function pctChange(current?: number, prior?: number): string | null {
  if (current == null || prior == null || prior <= 0) return null
  const pct = ((current - prior) / prior) * 100
  const sign = pct >= 0 ? "+" : ""
  return `${sign}${Math.round(pct)}% vs prior period`
}

function engagementRateInfoBody(
  bootstrap: ProfileInsightsBootstrapV1
): string {
  return (
    bootstrap.meta.engagement_rate_definition ??
    "Total engagement divided by content views in this period. Self-views are excluded. Stories are included in content views."
  )
}

function MetricTitleWithInfo({
  title,
  infoBody,
}: {
  title: string
  infoBody: string
}) {
  const [showsInfo, setShowsInfo] = useState(false)

  return (
    <div className="relative flex items-baseline gap-0.5">
      <p className="text-xs text-gray-400">{title}</p>
      <button
        type="button"
        className="rounded-full p-0.5 text-gray-500 hover:text-gray-300"
        aria-label={`About ${title}`}
        aria-expanded={showsInfo}
        onClick={() => setShowsInfo((open) => !open)}
      >
        <Info className="h-3.5 w-3.5" strokeWidth={2.25} aria-hidden />
      </button>
      {showsInfo ? (
        <div
          role="tooltip"
          className="absolute left-0 top-full z-20 mt-2 w-60 rounded-xl border border-white/10 bg-[#0f172a] p-3 text-left shadow-lg"
        >
          <p className="text-xs font-semibold text-white">{title}</p>
          <p className="mt-1 text-xs leading-relaxed text-gray-300">
            {infoBody}
          </p>
        </div>
      ) : null}
    </div>
  )
}

function MetricCard({
  title,
  value,
  priorPct,
  infoBody,
}: {
  title: string
  value: string
  priorPct?: string | null
  infoBody?: string
}) {
  return (
    <div className="rounded-xl border border-white/10 bg-white/5 p-4 backdrop-blur-md">
      {infoBody ? (
        <MetricTitleWithInfo title={title} infoBody={infoBody} />
      ) : (
        <p className="text-xs text-gray-400">{title}</p>
      )}
      <p className="mt-1 text-xl font-semibold tabular-nums text-white">
        {value}
      </p>
      {priorPct ? (
        <p className="mt-1 text-xs text-emerald-400/90">{priorPct}</p>
      ) : null}
    </div>
  )
}

function kindLabel(raw: string) {
  switch (raw) {
    case "post":
      return "Trades"
    case "profile_post":
      return "Posts"
    case "reel":
      return "Clips"
    case "achievement_post":
      return "Achievements"
    case "story":
      return "Stories"
    default:
      return raw
  }
}

function contentHref(row: TopContentRow): string | null {
  switch (row.content_kind) {
    case "post":
      return `/post/${row.content_id}`
    case "profile_post":
      return `/post/${row.content_id}`
    case "reel":
      return `/reel/${row.content_id}`
    case "achievement_post":
      return `/achievement/${row.content_id}`
    default:
      return null
  }
}

function ChartBlock({
  title,
  subtitle,
  points,
}: {
  title: string
  subtitle?: string
  points: { day: string; count: number }[]
}) {
  const data = useMemo(
    () =>
      points.map((p) => ({
        day: p.day.slice(5),
        count: p.count,
      })),
    [points]
  )
  if (!data.length) return null
  return (
    <section className="rounded-xl border border-white/10 bg-white/5 p-4 backdrop-blur-md">
      <h3 className="text-sm font-semibold text-white">{title}</h3>
      {subtitle ? (
        <p className="mt-1 text-xs text-gray-400">{subtitle}</p>
      ) : null}
      <div className="mt-3 h-40 w-full">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={data} margin={{ top: 4, right: 8, left: 0, bottom: 0 }}>
            <XAxis dataKey="day" tick={{ fill: "#9ca3af", fontSize: 10 }} />
            <YAxis tick={{ fill: "#9ca3af", fontSize: 10 }} width={28} />
            <Tooltip
              contentStyle={{
                background: "#0f172a",
                border: "1px solid rgba(255,255,255,0.1)",
                borderRadius: 8,
              }}
            />
            <Line type="monotone" dataKey="count" stroke="#34d399" dot={false} />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </section>
  )
}

export default function ProfileInsightsPageClient() {
  const router = useRouter()
  const { user, loading: authLoading } = useUserProfile()
  const [scope, setScope] = useState<ProfileInsightsScope>({
    kind: "preset",
    days: 30,
  })
  const [bootstrap, setBootstrap] =
    useState<ProfileInsightsBootstrapV1 | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [refreshing, setRefreshing] = useState(false)
  const [topSort, setTopSort] = useState<TopSort>("views")
  const [showsCustomRange, setShowsCustomRange] = useState(false)
  const [customDraftStart, setCustomDraftStart] = useState("")
  const [customDraftEnd, setCustomDraftEnd] = useState("")

  const query = useMemo(() => scopeToQuery(scope), [scope])

  const enabled =
    isBackendV2Enabled("profileInsights") ||
    isBackendV2Enabled("feedRotatingRank")

  const load = useCallback(async () => {
    if (!user?.id || !enabled) return
    const isRefresh = bootstrap != null
    if (isRefresh) setRefreshing(true)
    else setLoading(true)
    setError(null)
    try {
      const data = await fetchProfileInsightsBootstrap(supabase, query)
      if (data.meta.viewer_id !== user.id) {
        setError("Insights are only available for your own profile.")
        if (!isRefresh) setBootstrap(null)
        return
      }
      setBootstrap(data)
    } catch (e) {
      const message = e instanceof Error ? e.message : "Could not load insights."
      setError(message)
      if (!isRefresh) setBootstrap(null)
    } finally {
      setLoading(false)
      setRefreshing(false)
    }
  }, [bootstrap, enabled, query, user?.id])

  const openCustomRange = useCallback(() => {
    if (scope.kind === "custom") {
      setCustomDraftStart(scope.startYmd)
      setCustomDraftEnd(scope.endYmd)
    } else {
      setCustomDraftStart("")
      setCustomDraftEnd("")
    }
    setShowsCustomRange(true)
  }, [scope])

  const applyCustomRange = useCallback(() => {
    if (!customDraftStart.trim() || !customDraftEnd.trim()) return
    const start = customDraftStart.trim()
    const end = customDraftEnd.trim()
    const orderedStart = start <= end ? start : end
    const orderedEnd = start <= end ? end : start
    setScope({ kind: "custom", startYmd: orderedStart, endYmd: orderedEnd })
    setShowsCustomRange(false)
  }, [customDraftEnd, customDraftStart])

  useEffect(() => {
    if (authLoading) return
    if (!user?.id) {
      router.replace("/login")
      return
    }
    if (!enabled) return
    void load()
  }, [authLoading, enabled, load, router, user?.id])

  const topItems = useMemo(() => {
    if (!bootstrap) return []
    return topSort === "engagement"
      ? bootstrap.data.top_content_by_engagement ??
          bootstrap.data.top_content ??
          []
      : bootstrap.data.top_content_by_views ??
          bootstrap.data.top_content ??
          []
  }, [bootstrap, topSort])

  if (!enabled) {
    return (
      <main className="mx-auto max-w-3xl px-4 py-8 text-gray-300">
        Profile Insights is not enabled for this environment.
      </main>
    )
  }

  return (
    <main className="mx-auto max-w-3xl space-y-6 px-4 py-6 pb-24">
      <header className="flex items-center justify-between gap-4">
        <div>
          <Link
            href="/profile"
            className="text-sm text-gray-400 hover:text-white"
          >
            ← Profile
          </Link>
          <h1 className="mt-2 text-2xl font-semibold text-white">Insights</h1>
        </div>
      </header>

      <div className="flex flex-wrap gap-2">
        {PRESET_RANGES.map(({ days, label }) => (
          <button
            key={days}
            type="button"
            onClick={() => setScope({ kind: "preset", days })}
            className={`rounded-lg px-3 py-1.5 text-sm ${
              scope.kind === "preset" && scope.days === days
                ? "bg-emerald-500/20 text-emerald-200 ring-1 ring-emerald-400/40"
                : "bg-white/5 text-gray-300 hover:bg-white/10"
            }`}
          >
            {label}
          </button>
        ))}
        <button
          type="button"
          onClick={openCustomRange}
          className={`rounded-lg px-3 py-1.5 text-sm ${
            scope.kind === "custom"
              ? "bg-emerald-500/20 text-emerald-200 ring-1 ring-emerald-400/40"
              : "bg-white/5 text-gray-300 hover:bg-white/10"
          }`}
        >
          Custom
        </button>
      </div>

      {showsCustomRange ? (
        <div className="rounded-xl border border-white/10 bg-[#0f172a] p-4">
          <p className="mb-2 text-sm text-gray-400">Custom Range</p>
          <div className="flex flex-wrap items-center gap-2">
            <NativeDateInput
              value={customDraftStart}
              onChange={(e) => setCustomDraftStart(e.target.value)}
              className="h-11 min-w-0 flex-1 rounded-xl border border-blue-400/20 bg-[#0b2345] px-3 text-sm text-white"
              aria-label="Range start date"
            />
            <NativeDateInput
              value={customDraftEnd}
              onChange={(e) => setCustomDraftEnd(e.target.value)}
              className="h-11 min-w-0 flex-1 rounded-xl border border-blue-400/20 bg-[#0b2345] px-3 text-sm text-white"
              aria-label="Range end date"
            />
          </div>
          <div className="mt-3 flex flex-wrap gap-2">
            <button
              type="button"
              onClick={applyCustomRange}
              className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-medium text-white hover:bg-blue-600"
            >
              Apply Range
            </button>
            <button
              type="button"
              onClick={() => setShowsCustomRange(false)}
              className="rounded-lg bg-white/10 px-4 py-2 text-sm text-gray-300 hover:bg-white/20"
            >
              Cancel
            </button>
          </div>
        </div>
      ) : null}

      {loading && !bootstrap ? (
        <p className="text-sm text-gray-400">Loading insights…</p>
      ) : null}
      {refreshing ? (
        <p className="text-xs text-gray-500">Updating insights…</p>
      ) : null}
      {error ? (
        <div className="rounded-lg border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">
          {error}
          <button
            type="button"
            className="ml-3 underline"
            onClick={() => void load()}
          >
            Retry
          </button>
        </div>
      ) : null}

      {bootstrap ? (
        <>
          <section className="space-y-2 text-xs text-gray-400">
            {bootstrap.data.coverage.profile_visits_since ? (
              <p>
                Profile visits tracked since{" "}
                {new Date(
                  bootstrap.data.coverage.profile_visits_since
                ).toLocaleDateString()}
                .
              </p>
            ) : null}
            {bootstrap.data.coverage.content_views_since ? (
              <p>
                Content views tracked since{" "}
                {new Date(
                  bootstrap.data.coverage.content_views_since
                ).toLocaleDateString()}
                .
              </p>
            ) : (
              <p>Content view history starts when tracking is deployed.</p>
            )}
            {!bootstrap.data.coverage.follower_events_since ? (
              <p>
                Follower unfollows are tracked from deployment forward; earlier
                net growth may be incomplete.
              </p>
            ) : null}
          </section>

          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
            <MetricCard
              title="Profile visits"
              value={String(bootstrap.data.summary.profile_views ?? "—")}
              priorPct={pctChange(
                bootstrap.data.summary.profile_views,
                bootstrap.data.summary_prior.profile_views
              )}
            />
            <MetricCard
              title="Unique visitors"
              value={String(bootstrap.data.summary.unique_visitors ?? "—")}
              priorPct={pctChange(
                bootstrap.data.summary.unique_visitors,
                bootstrap.data.summary_prior.unique_visitors
              )}
            />
            <MetricCard
              title="Content views"
              value={String(bootstrap.data.summary.content_views ?? "—")}
              priorPct={pctChange(
                bootstrap.data.summary.content_views,
                bootstrap.data.summary_prior.content_views
              )}
            />
            <MetricCard
              title="Net followers"
              value={String(bootstrap.data.summary.net_followers ?? "—")}
              priorPct={pctChange(
                bootstrap.data.summary.net_followers,
                bootstrap.data.summary_prior.net_followers
              )}
            />
            <MetricCard
              title="Engagement"
              value={String(bootstrap.data.summary.total_engagement ?? "—")}
              priorPct={pctChange(
                bootstrap.data.summary.total_engagement,
                bootstrap.data.summary_prior.total_engagement
              )}
            />
            <MetricCard
              title="Engagement rate"
              value={
                bootstrap.data.summary.engagement_rate != null
                  ? `${(bootstrap.data.summary.engagement_rate * 100).toFixed(1)}%`
                  : "—"
              }
              infoBody={engagementRateInfoBody(bootstrap)}
            />
          </div>

          <ChartBlock
            title="Net follower growth"
            subtitle="Follows minus unfollows per day after follower event tracking started."
            points={bootstrap.data.series.follower_net_per_day ?? []}
          />
          <ChartBlock
            title="New followers"
            points={bootstrap.data.series.new_followers_per_day ?? []}
          />
          <ChartBlock
            title="Unfollows"
            points={bootstrap.data.series.unfollows_per_day ?? []}
          />

          <section className="rounded-xl border border-white/10 bg-white/5 p-4">
            <h3 className="text-sm font-semibold text-white">
              Content views by type
            </h3>
            <ul className="mt-3 space-y-2 text-sm text-gray-300">
              {Object.entries(bootstrap.data.content_views_by_kind ?? {})
                .sort(([a], [b]) => a.localeCompare(b))
                .map(([k, n]) => (
                  <li key={k} className="flex justify-between">
                    <span>{kindLabel(k)}</span>
                    <span className="tabular-nums text-gray-400">{n}</span>
                  </li>
                ))}
            </ul>
          </section>

          <section className="rounded-xl border border-white/10 bg-white/5 p-4">
            <h3 className="text-sm font-semibold text-white">
              Engagement breakdown
            </h3>
            <ul className="mt-3 space-y-2 text-sm text-gray-300">
              <li className="flex justify-between">
                <span>Likes</span>
                <span>{bootstrap.data.summary.likes ?? "—"}</span>
              </li>
              <li className="flex justify-between">
                <span>Comments</span>
                <span>{bootstrap.data.summary.comments ?? "—"}</span>
              </li>
              <li className="flex justify-between">
                <span>Saves</span>
                <span>{bootstrap.data.summary.saves ?? "—"}</span>
              </li>
              <li className="flex justify-between">
                <span>Shares (initiated)</span>
                <span>{bootstrap.data.summary.shares_initiated ?? "—"}</span>
              </li>
              <li className="flex justify-between">
                <span>Shares (completed)</span>
                <span>{bootstrap.data.summary.shares_completed ?? "—"}</span>
              </li>
            </ul>
          </section>

          <section className="rounded-xl border border-white/10 bg-white/5 p-4">
            <div className="flex items-center justify-between gap-2">
              <h3 className="text-sm font-semibold text-white">Top content</h3>
              <select
                value={topSort}
                onChange={(e) => setTopSort(e.target.value as TopSort)}
                className="rounded-md border border-white/10 bg-[#0f172a] px-2 py-1 text-xs text-gray-200"
              >
                <option value="views">Views</option>
                <option value="engagement">Engagement</option>
              </select>
            </div>
            {topItems.length === 0 ? (
              <p className="mt-3 text-sm text-gray-400">
                No ranked content in this period yet.
              </p>
            ) : (
              <ul className="mt-3 divide-y divide-white/10">
                {topItems.map((row) => {
                  const href = contentHref(row)
                  const inner = (
                    <>
                      <span className="font-medium text-white">
                        {kindLabel(row.content_kind)}
                      </span>
                      <span className="text-xs text-gray-400">
                        {row.views} views · {row.engagement} engagement
                      </span>
                    </>
                  )
                  return (
                    <li key={`${row.content_kind}:${row.content_id}`}>
                      {href ? (
                        <Link
                          href={href}
                          className="flex flex-col gap-0.5 py-3 hover:bg-white/5"
                        >
                          {inner}
                        </Link>
                      ) : (
                        <div className="flex flex-col gap-0.5 py-3">{inner}</div>
                      )}
                    </li>
                  )
                })}
              </ul>
            )}
          </section>
        </>
      ) : null}
    </main>
  )
}