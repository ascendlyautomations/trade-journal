"use client"

import Link from "next/link"
import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import EmptyState from "@/app/components/ui/EmptyState"
import { getCurrentAdminCheckResult } from "@/lib/adminUsers"
import {
  FEATURE_REQUEST_STATUS_OPTIONS,
  type FeatureRequestRow,
  type FeatureRequestStatus,
} from "@/lib/featureRequests"
import { supabase } from "@/lib/supabaseClient"

type StatusFilter = "all" | FeatureRequestStatus

function previewText(text: string | null | undefined, max = 120) {
  const t = (text || "").replace(/\s+/g, " ").trim()
  if (!t) return "—"
  return t.length > max ? `${t.slice(0, max)}…` : t
}

function statusBadgeClass(status: FeatureRequestStatus) {
  switch (status) {
    case "planned":
      return "bg-blue-500/25 text-blue-100"
    case "completed":
      return "bg-emerald-500/25 text-emerald-100"
    default:
      return "bg-amber-500/20 text-amber-100"
  }
}

export default function AdminFeatureRequestsPage() {
  const router = useRouter()
  const [checking, setChecking] = useState(true)
  const [allowed, setAllowed] = useState(false)
  const [rows, setRows] = useState<FeatureRequestRow[]>([])
  const [listLoading, setListLoading] = useState(false)
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("open")
  const [search, setSearch] = useState("")
  const [debouncedSearch, setDebouncedSearch] = useState("")
  const [selected, setSelected] = useState<FeatureRequestRow | null>(null)
  const [detailStatus, setDetailStatus] = useState<FeatureRequestStatus>("open")
  const [savingDetail, setSavingDetail] = useState(false)

  useEffect(() => {
    const t = window.setTimeout(() => setDebouncedSearch(search), 300)
    return () => window.clearTimeout(t)
  }, [search])

  async function fetchRows() {
    if (!allowed) return
    setListLoading(true)

    let query = supabase
      .from("feature_requests")
      .select("id, user_id, title, description, status, created_at")
      .order("created_at", { ascending: false })

    if (statusFilter !== "all") {
      query = query.eq("status", statusFilter)
    }

    const q = debouncedSearch.trim()
    if (q) {
      query = query.or(`title.ilike.%${q}%,description.ilike.%${q}%`)
    }

    const { data, error } = await query
    if (error) {
      console.error("[admin-feature-requests] fetch failed", error)
      setRows([])
    } else {
      setRows((data as FeatureRequestRow[]) || [])
    }
    setListLoading(false)
  }

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
    void fetchRows()
  }, [allowed, statusFilter, debouncedSearch])

  const filteredCountLabel = useMemo(() => {
    const parts: string[] = []
    if (statusFilter !== "all") parts.push(statusFilter)
    if (debouncedSearch.trim()) parts.push(`search: "${debouncedSearch.trim()}"`)
    return parts.length ? parts.join(" · ") : "all requests"
  }, [statusFilter, debouncedSearch])

  function openDetail(row: FeatureRequestRow) {
    setSelected(row)
    setDetailStatus(row.status)
  }

  async function handleSaveDetail() {
    if (!selected?.id) return
    setSavingDetail(true)

    const { error } = await supabase
      .from("feature_requests")
      .update({ status: detailStatus })
      .eq("id", selected.id)

    if (error) {
      console.error("[admin-feature-requests] save failed", error)
      alert("Failed to update feature request.")
      setSavingDetail(false)
      return
    }

    setSelected(null)
    setSavingDetail(false)
    await fetchRows()
  }

  const filterBtn = (
    key: string,
    active: boolean,
    label: string,
    onClick: () => void
  ) => (
    <button
      key={key}
      type="button"
      onClick={onClick}
      className={`rounded px-3 py-1.5 text-sm ${
        active ? "bg-blue-500 text-white" : "bg-white/10 text-gray-200 hover:bg-white/20"
      }`}
    >
      {label}
    </button>
  )

  if (checking || !allowed) {
    return (
      <>
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-8 text-white">
          Checking admin access...
        </div>
      </>
    )
  }

  return (
    <>
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-4 text-gray-100 md:p-8">
        <div className="mx-auto max-w-6xl space-y-6">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h1 className="text-2xl font-bold text-blue-300 md:text-3xl">
              Feature requests
            </h1>
            <Link href="/admin" className="rounded bg-white/10 px-3 py-2 text-sm hover:bg-white/20">
              Back to Admin
            </Link>
          </div>

          <section className="rounded-xl border border-white/10 bg-white/5 p-5">
            <p className="mb-3 text-sm text-gray-400">
              Beta tester feature requests from /beta. Search by title or description, filter by status, then open a
              request to update triage state.
            </p>

            <input
              type="search"
              placeholder="Search title or description…"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="mb-4 w-full max-w-md rounded-lg border border-white/10 bg-black/20 px-3 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-400/50"
            />

            <div>
              <p className="mb-2 text-xs uppercase tracking-wide text-gray-500">Status</p>
              <div className="flex flex-wrap gap-2">
                {filterBtn("status-all", statusFilter === "all", "All", () => setStatusFilter("all"))}
                {FEATURE_REQUEST_STATUS_OPTIONS.map((opt) =>
                  filterBtn(
                    `status-${opt.value}`,
                    statusFilter === opt.value,
                    opt.label,
                    () => setStatusFilter(opt.value)
                  )
                )}
              </div>
            </div>

            <p className="mt-4 text-xs text-gray-500">
              Showing {filteredCountLabel} ({rows.length} {rows.length === 1 ? "request" : "requests"})
            </p>

            {listLoading ? (
              <p className="mt-4 text-sm text-gray-300">Loading requests...</p>
            ) : !rows.length ? (
              statusFilter === "all" && !debouncedSearch.trim() ? (
                <EmptyState
                  title="No Feature Requests Yet"
                  description="Beta testers haven't submitted any feature requests."
                  className="mt-4 py-8"
                />
              ) : (
                <EmptyState
                  title="No Matching Requests"
                  description="Try adjusting your filters."
                  className="mt-4 py-8"
                />
              )
            ) : (
              <div className="mt-4 space-y-2">
                {rows.map((row) => (
                  <button
                    key={row.id}
                    type="button"
                    onClick={() => openDetail(row)}
                    className="w-full rounded-lg border border-white/10 bg-black/20 p-3 text-left transition hover:bg-black/30"
                  >
                    <div className="flex flex-wrap items-start justify-between gap-2">
                      <p className="min-w-0 flex-1 truncate font-medium text-white">{row.title}</p>
                      <span
                        className={`shrink-0 rounded px-2 py-0.5 text-xs capitalize ${statusBadgeClass(row.status)}`}
                      >
                        {row.status}
                      </span>
                    </div>
                    <p className="mt-1 line-clamp-2 text-sm text-gray-300">{previewText(row.description)}</p>
                    <div className="mt-2 flex flex-wrap items-center justify-between gap-2 text-xs text-gray-500">
                      <span className="truncate">{row.user_id}</span>
                      <span className="shrink-0 tabular-nums">
                        {row.created_at ? new Date(row.created_at).toLocaleString() : "—"}
                      </span>
                    </div>
                  </button>
                ))}
              </div>
            )}
          </section>
        </div>
      </div>

      {selected ? (
        <div
          className="fixed inset-0 z-[130] flex items-center justify-center bg-black/70 p-3 backdrop-blur-sm md:p-6"
          onClick={() => setSelected(null)}
        >
          <div
            className="max-h-[90vh] w-full max-w-3xl overflow-y-auto rounded-xl border border-white/10 bg-[#0f172a] p-4 text-white md:p-6"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="mb-4 flex flex-wrap items-start justify-between gap-3">
              <div className="min-w-0 flex-1">
                <p className="text-xs text-gray-400">
                  {selected.status} · {selected.created_at ? new Date(selected.created_at).toLocaleString() : "—"}
                </p>
                <h3 className="mt-1 text-xl font-semibold">{selected.title}</h3>
                <p className="mt-1 text-xs text-gray-400">User: {selected.user_id}</p>
              </div>
              <div className="flex shrink-0 flex-wrap items-center gap-2">
                <button
                  type="button"
                  onClick={() => void handleSaveDetail()}
                  disabled={savingDetail}
                  className="rounded bg-blue-500 px-3 py-2 text-sm font-semibold hover:bg-blue-600 disabled:opacity-60"
                >
                  {savingDetail ? "Saving..." : "Save status"}
                </button>
                <button
                  type="button"
                  onClick={() => setSelected(null)}
                  className="rounded bg-white/10 px-3 py-2 text-sm hover:bg-white/20"
                >
                  Close
                </button>
              </div>
            </div>

            <label className="block text-xs uppercase tracking-wide text-gray-500">
              Status
              <select
                value={detailStatus}
                onChange={(e) => setDetailStatus(e.target.value as FeatureRequestStatus)}
                className="mt-1 w-full rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white"
              >
                {FEATURE_REQUEST_STATUS_OPTIONS.map((opt) => (
                  <option key={opt.value} value={opt.value}>
                    {opt.label}
                  </option>
                ))}
              </select>
            </label>

            <div className="mt-4">
              <p className="text-xs uppercase tracking-wide text-gray-500">Description</p>
              <p className="mt-2 whitespace-pre-wrap text-sm text-gray-200">{selected.description}</p>
            </div>
          </div>
        </div>
      ) : null}
    </>
  )
}
