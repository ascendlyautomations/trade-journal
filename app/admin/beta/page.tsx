"use client"

import Link from "next/link"
import { useCallback, useEffect, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import {
  activityRowKey,
  betaActivityKindLabel,
  BETA_ACTIVITY_PAGE_SIZE,
  fetchAdminBetaActivity,
  fetchAdminBetaDashboardBundle,
  mergeActivityRows,
  type AdminBetaDashboardBundle,
  type BetaDashboardActivityItem,
} from "@/lib/adminBetaDashboard"
import { getCurrentAdminCheckResult } from "@/lib/adminUsers"
import { supabase } from "@/lib/supabaseClient"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"

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

function formatWhen(iso: string) {
  if (!iso) return "—"
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return "—"
  return d.toLocaleString()
}

export default function AdminBetaDashboardPage() {
  const router = useRouter()
  const [checking, setChecking] = useState(true)
  const [allowed, setAllowed] = useState(false)
  const [bundle, setBundle] = useState<AdminBetaDashboardBundle | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  const [activityRows, setActivityRows] = useState<BetaDashboardActivityItem[]>([])
  const [activityLoading, setActivityLoading] = useState(false)
  const [activityLoadingMore, setActivityLoadingMore] = useState(false)
  const [activityError, setActivityError] = useState<string | null>(null)
  const [hasMoreActivity, setHasMoreActivity] = useState(false)
  const [activitySearch, setActivitySearch] = useState("")
  const [debouncedActivitySearch, setDebouncedActivitySearch] = useState("")
  const activityGenerationRef = useRef(0)

  useEffect(() => {
    const t = window.setTimeout(() => setDebouncedActivitySearch(activitySearch), 300)
    return () => window.clearTimeout(t)
  }, [activitySearch])

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
      setLoading(true)
      const { data, error } = await fetchAdminBetaDashboardBundle(supabase)
      if (cancelled) return
      setLoading(false)
      if (error) {
        setLoadError(toUserFacingErrorMessage(error))
        setBundle(null)
        return
      }
      setLoadError(null)
      setBundle(data)
    })()
    return () => {
      cancelled = true
    }
  }, [allowed])

  const loadActivity = useCallback(
    async (opts: { offset: number; search: string; append: boolean }) => {
      if (!allowed) return

      if (!opts.append) {
        activityGenerationRef.current += 1
      }
      const generation = activityGenerationRef.current

      if (opts.append) {
        setActivityLoadingMore(true)
      } else {
        setActivityLoading(true)
      }

      const { data, error } = await fetchAdminBetaActivity(supabase, {
        limit: BETA_ACTIVITY_PAGE_SIZE,
        offset: opts.offset,
        search: opts.search.trim() || null,
      })

      if (generation !== activityGenerationRef.current) {
        if (opts.append) setActivityLoadingMore(false)
        else setActivityLoading(false)
        return
      }

      if (opts.append) {
        setActivityLoadingMore(false)
      } else {
        setActivityLoading(false)
      }

      if (error) {
        setActivityError(toUserFacingErrorMessage(error))
        if (!opts.append) setActivityRows([])
        setHasMoreActivity(false)
        return
      }

      setActivityError(null)
      setActivityRows((prev) => mergeActivityRows(prev, data, opts.append))
      setHasMoreActivity(data.length === BETA_ACTIVITY_PAGE_SIZE)
    },
    [allowed]
  )

  useEffect(() => {
    if (!allowed) return
    void loadActivity({ offset: 0, search: debouncedActivitySearch, append: false })
  }, [allowed, debouncedActivitySearch, loadActivity])

  if (checking || !allowed) {
    return (
      <>
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-8 text-white">
          Checking admin access...
        </div>
      </>
    )
  }

  const m = bundle

  return (
    <>
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100 p-4 md:p-8">
        <div className="mx-auto max-w-6xl space-y-8">
          <div className="flex flex-wrap items-end justify-between gap-3">
            <div>
              <Link href="/admin" className="text-sm text-blue-300 hover:text-blue-200">
                ← Admin
              </Link>
              <h1 className="mt-2 text-2xl font-bold text-blue-300 md:text-3xl">
                Beta Dashboard
              </h1>
              <p className="mt-1 text-sm text-gray-400">
                Beta tester engagement, participation, and submission queues.
              </p>
            </div>
            {loading ? <p className="text-sm text-gray-500">Refreshing metrics…</p> : null}
          </div>

          {loadError ? (
            <div className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-100">
              Could not load beta dashboard metrics. Apply the{" "}
              <code className="rounded bg-black/30 px-1">admin_beta_dashboard_bundle</code> migration, then
              refresh. {loadError}
            </div>
          ) : null}

          <section className="space-y-3">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">Beta testers</h2>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <MetricCard label="Total beta testers" value={m?.totalBetaTesters ?? "—"} />
              <MetricCard
                label="Active beta testers (7d)"
                value={m?.activeBetaTesters7d ?? "—"}
                hint="Distinct users with trades, profile posts, or room messages in the last 7 days"
              />
            </div>
          </section>

          <section className="space-y-3">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">Trades logged</h2>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <MetricCard label="Total (beta testers)" value={m?.tradesTotal ?? "—"} />
              <MetricCard label="Last 7 days" value={m?.trades7d ?? "—"} />
            </div>
          </section>

          <section className="space-y-3">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">Posts created</h2>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <MetricCard
                label="Total (beta testers)"
                value={m?.postsTotal ?? "—"}
                hint="Profile wall posts"
              />
              <MetricCard label="Last 7 days" value={m?.posts7d ?? "—"} />
            </div>
          </section>

          <section className="space-y-3">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">
              Beta room participation
            </h2>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <MetricCard label="Room members" value={m?.betaRoomMembers ?? "—"} hint="tradetraxs-beta" />
              <MetricCard label="Room messages" value={m?.betaRoomMessages ?? "—"} hint="tradetraxs-beta" />
            </div>
          </section>

          <section className="space-y-3">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">Bug reports</h2>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
              <MetricCard label="Total" value={m?.bugReportsTotal ?? "—"} />
              <MetricCard label="Open" value={m?.bugReportsOpen ?? "—"} />
              <MetricCard label="Resolved" value={m?.bugReportsResolved ?? "—"} />
            </div>
          </section>

          <section className="space-y-3">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">Feature requests</h2>
            <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
              <MetricCard label="Total" value={m?.featureRequestsTotal ?? "—"} />
              <MetricCard label="Open" value={m?.featureRequestsOpen ?? "—"} />
              <MetricCard label="Planned" value={m?.featureRequestsPlanned ?? "—"} />
              <MetricCard label="Completed" value={m?.featureRequestsCompleted ?? "—"} />
            </div>
          </section>

          <section className="rounded-xl border border-white/10 bg-white/5 p-5">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">Recent beta activity</h2>
            <p className="mt-1 text-xs text-gray-500">
              Bug reports, feature requests, beta room messages, and beta tester trades, newest first.
            </p>

            <div className="mt-4">
              <input
                type="search"
                value={activitySearch}
                onChange={(e) => setActivitySearch(e.target.value)}
                placeholder="Search by username or user ID…"
                className="w-full max-w-md rounded-lg border border-white/10 bg-black/20 px-3 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-400/40"
              />
            </div>

            {activityError ? (
              <p className="mt-3 text-sm text-amber-200/90">
                Could not load activity. Apply the{" "}
                <code className="rounded bg-black/30 px-1">admin_beta_activity</code> migration. {activityError}
              </p>
            ) : null}

            {activityLoading && activityRows.length === 0 ? (
              <p className="mt-4 text-sm text-gray-500">Loading activity…</p>
            ) : !activityRows.length ? (
              <p className="mt-4 text-sm text-gray-500">
                {debouncedActivitySearch.trim() ? "No activity matches your search." : "No recent activity yet."}
              </p>
            ) : (
              <div className="mt-4 overflow-x-auto">
                <table className="w-full min-w-[640px] text-left text-sm">
                  <thead>
                    <tr className="border-b border-white/10 text-xs uppercase tracking-wide text-gray-500">
                      <th className="pb-2 pr-4 font-medium">When</th>
                      <th className="pb-2 pr-4 font-medium">Type</th>
                      <th className="pb-2 pr-4 font-medium">User</th>
                      <th className="pb-2 font-medium">Summary</th>
                    </tr>
                  </thead>
                  <tbody>
                    {activityRows.map((row) => (
                      <tr key={activityRowKey(row)} className="border-b border-white/5 last:border-0">
                        <td className="py-2.5 pr-4 tabular-nums text-gray-400 whitespace-nowrap">
                          {formatWhen(row.createdAt)}
                        </td>
                        <td className="py-2.5 pr-4 text-gray-200 whitespace-nowrap">
                          {betaActivityKindLabel(row.kind)}
                        </td>
                        <td className="py-2.5 pr-4 text-gray-300 whitespace-nowrap">
                          {row.username || row.userId.slice(0, 8) || "—"}
                        </td>
                        <td className="py-2.5 text-gray-200">{row.summary}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}

            {hasMoreActivity && !activityLoading ? (
              <button
                type="button"
                disabled={activityLoadingMore}
                onClick={() =>
                  void loadActivity({
                    offset: activityRows.length,
                    search: debouncedActivitySearch,
                    append: true,
                  })
                }
                className="mt-4 rounded-lg border border-white/15 bg-white/5 px-4 py-2 text-sm font-medium text-gray-200 transition hover:border-white/25 hover:bg-white/10 disabled:opacity-60"
              >
                {activityLoadingMore ? "Loading…" : "Load More"}
              </button>
            ) : null}
          </section>
        </div>
      </div>
    </>
  )
}
