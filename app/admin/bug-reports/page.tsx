"use client"

import Link from "next/link"
import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { getCurrentAdminCheckResult } from "@/lib/adminUsers"
import {
  BUG_REPORT_SEVERITY_OPTIONS,
  BUG_REPORT_STATUS_OPTIONS,
  type BugReportRow,
  type BugReportSeverity,
  type BugReportStatus,
} from "@/lib/bugReports"
import { supabase } from "@/lib/supabaseClient"

type StatusFilter = "all" | BugReportStatus
type SeverityFilter = "all" | BugReportSeverity

function previewText(text: string | null | undefined, max = 120) {
  const t = (text || "").replace(/\s+/g, " ").trim()
  if (!t) return "—"
  return t.length > max ? `${t.slice(0, max)}…` : t
}

function severityBadgeClass(severity: BugReportSeverity) {
  switch (severity) {
    case "critical":
      return "bg-red-500/25 text-red-100"
    case "high":
      return "bg-orange-500/25 text-orange-100"
    case "medium":
      return "bg-amber-500/20 text-amber-100"
    default:
      return "bg-white/10 text-gray-200"
  }
}

export default function AdminBugReportsPage() {
  const router = useRouter()
  const [checking, setChecking] = useState(true)
  const [allowed, setAllowed] = useState(false)
  const [rows, setRows] = useState<BugReportRow[]>([])
  const [listLoading, setListLoading] = useState(false)
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("open")
  const [severityFilter, setSeverityFilter] = useState<SeverityFilter>("all")
  const [selected, setSelected] = useState<BugReportRow | null>(null)
  const [detailStatus, setDetailStatus] = useState<BugReportStatus>("open")
  const [savingDetail, setSavingDetail] = useState(false)
  const [lightboxUrl, setLightboxUrl] = useState<string | null>(null)

  async function fetchRows() {
    if (!allowed) return
    setListLoading(true)

    let query = supabase
      .from("bug_reports")
      .select(
        "id, user_id, title, description, screenshot_url, page_url, browser_info, severity, status, created_at, resolved_at"
      )
      .order("created_at", { ascending: false })

    if (statusFilter !== "all") {
      query = query.eq("status", statusFilter)
    }
    if (severityFilter !== "all") {
      query = query.eq("severity", severityFilter)
    }

    const { data, error } = await query
    if (error) {
      console.error("[admin-bug-reports] fetch failed", error)
      setRows([])
    } else {
      setRows((data as BugReportRow[]) || [])
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
  }, [allowed, statusFilter, severityFilter])

  const filteredCountLabel = useMemo(() => {
    const parts: string[] = []
    if (statusFilter !== "all") parts.push(statusFilter.replace("_", " "))
    if (severityFilter !== "all") parts.push(severityFilter)
    return parts.length ? parts.join(" · ") : "all reports"
  }, [statusFilter, severityFilter])

  function openDetail(row: BugReportRow) {
    setSelected(row)
    setDetailStatus(row.status)
  }

  async function handleSaveDetail() {
    if (!selected?.id) return
    setSavingDetail(true)

    const resolved = detailStatus === "resolved"
    const updatePayload: Record<string, unknown> = {
      status: detailStatus,
      resolved_at: resolved
        ? selected.status === "resolved" && selected.resolved_at
          ? selected.resolved_at
          : new Date().toISOString()
        : null,
    }

    const { error } = await supabase.from("bug_reports").update(updatePayload).eq("id", selected.id)

    if (error) {
      console.error("[admin-bug-reports] save failed", error)
      alert("Failed to update bug report.")
      setSavingDetail(false)
      return
    }

    setSelected(null)
    setSavingDetail(false)
    await fetchRows()
  }

  async function handleMarkResolved() {
    if (!selected?.id) return
    setDetailStatus("resolved")
    setSavingDetail(true)

    const { error } = await supabase
      .from("bug_reports")
      .update({
        status: "resolved",
        resolved_at: new Date().toISOString(),
      })
      .eq("id", selected.id)

    if (error) {
      console.error("[admin-bug-reports] resolve failed", error)
      alert("Failed to mark report resolved.")
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
              Bug reports
            </h1>
            <Link href="/admin" className="rounded bg-white/10 px-3 py-2 text-sm hover:bg-white/20">
              Back to Admin
            </Link>
          </div>

          <section className="rounded-xl border border-white/10 bg-white/5 p-5">
            <p className="mb-3 text-sm text-gray-400">
              Beta tester bug submissions. Filter by status and severity, then open a report to review context and
              screenshots.
            </p>

            <div className="space-y-3">
              <div>
                <p className="mb-2 text-xs uppercase tracking-wide text-gray-500">Status</p>
                <div className="flex flex-wrap gap-2">
                  {filterBtn("status-all", statusFilter === "all", "All", () => setStatusFilter("all"))}
                  {BUG_REPORT_STATUS_OPTIONS.map((opt) =>
                    filterBtn(
                      `status-${opt.value}`,
                      statusFilter === opt.value,
                      opt.label,
                      () => setStatusFilter(opt.value)
                    )
                  )}
                </div>
              </div>

              <div>
                <p className="mb-2 text-xs uppercase tracking-wide text-gray-500">Severity</p>
                <div className="flex flex-wrap gap-2">
                  {filterBtn("severity-all", severityFilter === "all", "All", () => setSeverityFilter("all"))}
                  {BUG_REPORT_SEVERITY_OPTIONS.map((opt) =>
                    filterBtn(
                      `severity-${opt.value}`,
                      severityFilter === opt.value,
                      opt.value.charAt(0).toUpperCase() + opt.value.slice(1),
                      () => setSeverityFilter(opt.value)
                    )
                  )}
                </div>
              </div>
            </div>

            <p className="mt-4 text-xs text-gray-500">
              Showing {filteredCountLabel} ({rows.length} {rows.length === 1 ? "report" : "reports"})
            </p>

            {listLoading ? (
              <p className="mt-4 text-sm text-gray-300">Loading reports...</p>
            ) : !rows.length ? (
              <p className="mt-4 text-sm text-gray-300">No bug reports match these filters.</p>
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
                      <div className="flex shrink-0 flex-wrap items-center gap-1.5">
                        <span
                          className={`rounded px-2 py-0.5 text-xs capitalize ${severityBadgeClass(row.severity)}`}
                        >
                          {row.severity}
                        </span>
                        <span className="rounded bg-emerald-500/20 px-2 py-0.5 text-xs capitalize text-emerald-200">
                          {row.status.replace("_", " ")}
                        </span>
                        {row.screenshot_url ? (
                          <span className="rounded bg-blue-500/25 px-2 py-0.5 text-xs text-blue-100">Screenshot</span>
                        ) : null}
                      </div>
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
                  {selected.severity} · {selected.status.replace("_", " ")} ·{" "}
                  {selected.created_at ? new Date(selected.created_at).toLocaleString() : "—"}
                </p>
                <h3 className="mt-1 text-xl font-semibold">{selected.title}</h3>
                <p className="mt-1 text-xs text-gray-400">User: {selected.user_id}</p>
              </div>
              <div className="flex shrink-0 flex-wrap items-center gap-2">
                {selected.status !== "resolved" ? (
                  <button
                    type="button"
                    onClick={() => void handleMarkResolved()}
                    disabled={savingDetail}
                    className="rounded bg-emerald-500 px-3 py-2 text-sm font-semibold hover:bg-emerald-600 disabled:opacity-60"
                  >
                    {savingDetail ? "Saving..." : "Mark resolved"}
                  </button>
                ) : null}
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

            <div className="space-y-4">
              <div className="rounded border border-white/10 bg-black/20 p-3">
                <p className="text-xs text-gray-400">Description</p>
                <p className="mt-1 whitespace-pre-wrap text-sm text-gray-200">{selected.description || "—"}</p>
              </div>

              <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
                <div className="rounded border border-white/10 bg-black/20 p-3">
                  <p className="text-xs text-gray-400">Page URL</p>
                  <p className="mt-1 break-all text-sm text-gray-200">{selected.page_url || "—"}</p>
                </div>
                <div className="rounded border border-white/10 bg-black/20 p-3">
                  <p className="text-xs text-gray-400">Browser</p>
                  <p className="mt-1 break-all text-sm text-gray-200">{selected.browser_info || "—"}</p>
                </div>
              </div>

              {selected.screenshot_url ? (
                <div className="rounded border border-white/10 bg-black/20 p-3">
                  <p className="mb-2 text-xs text-gray-400">Screenshot</p>
                  <img
                    src={selected.screenshot_url}
                    alt=""
                    className="max-h-[320px] w-full cursor-zoom-in rounded border border-white/10 bg-black/40 object-contain"
                    onClick={() => setLightboxUrl(selected.screenshot_url)}
                  />
                </div>
              ) : null}

              <div className="rounded border border-white/10 bg-black/20 p-3">
                <label className="text-xs text-gray-400">Status</label>
                <select
                  value={detailStatus}
                  onChange={(e) => setDetailStatus(e.target.value as BugReportStatus)}
                  className="mt-1 w-full rounded border border-white/10 bg-[#111827] p-2 text-sm"
                >
                  {BUG_REPORT_STATUS_OPTIONS.map((opt) => (
                    <option key={opt.value} value={opt.value}>
                      {opt.label}
                    </option>
                  ))}
                </select>
                {selected.resolved_at ? (
                  <p className="mt-2 text-xs text-gray-500">
                    Resolved at {new Date(selected.resolved_at).toLocaleString()}
                  </p>
                ) : null}
              </div>
            </div>
          </div>
        </div>
      ) : null}

      {lightboxUrl ? (
        <div
          className="fixed inset-0 z-[140] flex items-center justify-center bg-black/85 p-3"
          onClick={() => setLightboxUrl(null)}
        >
          <div className="relative w-full max-w-5xl" onClick={(e) => e.stopPropagation()}>
            <button
              type="button"
              onClick={() => setLightboxUrl(null)}
              className="absolute right-0 top-0 z-10 rounded bg-black/60 px-3 py-1 text-sm text-white hover:bg-black/80"
            >
              Close
            </button>
            <img src={lightboxUrl} alt="" className="max-h-[85vh] w-full rounded object-contain" />
          </div>
        </div>
      ) : null}
    </>
  )
}
