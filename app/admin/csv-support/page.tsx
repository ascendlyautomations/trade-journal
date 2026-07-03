"use client"

import Link from "next/link"
import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { getCurrentAdminCheckResult } from "@/lib/adminUsers"
import {
  CSV_SUPPORT_STATUS_OPTIONS,
  createCsvSupportSignedDownloadUrl,
  csvStorageFilename,
  csvSupportStatusLabel,
  formatCsvSupportUserLabel,
  type CsvSupportProfileHint,
  type CsvSupportRequestRow,
  type CsvSupportRequestStatus,
} from "@/lib/adminCsvSupport"
import { supabase } from "@/lib/supabaseClient"

type StatusFilter = "all" | CsvSupportRequestStatus

function previewText(text: string | null | undefined, max = 140) {
  const t = (text || "").replace(/\s+/g, " ").trim()
  if (!t) return "—"
  return t.length > max ? `${t.slice(0, max)}…` : t
}

function statusBadgeClass(status: string) {
  switch (status) {
    case "new":
      return "bg-blue-500/25 text-blue-100"
    case "in_progress":
      return "bg-amber-500/20 text-amber-100"
    case "resolved":
      return "bg-emerald-500/25 text-emerald-100"
    case "closed":
      return "bg-red-500/20 text-red-100"
    default:
      return "bg-white/10 text-gray-200"
  }
}

export default function AdminCsvSupportPage() {
  const router = useRouter()
  const [checking, setChecking] = useState(true)
  const [allowed, setAllowed] = useState(false)
  const [rows, setRows] = useState<CsvSupportRequestRow[]>([])
  const [profilesByUserId, setProfilesByUserId] = useState<
    Record<string, CsvSupportProfileHint>
  >({})
  const [listLoading, setListLoading] = useState(false)
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("new")
  const [selected, setSelected] = useState<CsvSupportRequestRow | null>(null)
  const [detailStatus, setDetailStatus] = useState<CsvSupportRequestStatus>("new")
  const [savingDetail, setSavingDetail] = useState(false)
  const [downloadingId, setDownloadingId] = useState<string | null>(null)

  async function loadProfilesForRows(requestRows: CsvSupportRequestRow[]) {
    const userIds = [
      ...new Set(
        requestRows.map((r) => r.user_id).filter((id): id is string => Boolean(id))
      ),
    ]
    if (!userIds.length) {
      setProfilesByUserId({})
      return
    }

    const { data, error } = await supabase
      .from("profiles")
      .select("id, username, name, is_beta_tester")
      .in("id", userIds)

    if (error) {
      console.error("[admin-csv-support] profile fetch failed", error)
      return
    }

    const map: Record<string, CsvSupportProfileHint> = {}
    for (const row of data || []) {
      if (row?.id) {
        map[String(row.id)] = {
          id: String(row.id),
          username: row.username != null ? String(row.username) : null,
          name: row.name != null ? String(row.name) : null,
          is_beta_tester:
            typeof row.is_beta_tester === "boolean" ? row.is_beta_tester : null,
        }
      }
    }
    setProfilesByUserId(map)
  }

  async function fetchRows() {
    if (!allowed) return
    setListLoading(true)

    let query = supabase
      .from("csv_support_requests")
      .select("id, user_id, broker_name, notes, csv_file_url, created_at, status")
      .order("created_at", { ascending: false })

    if (statusFilter !== "all") {
      query = query.eq("status", statusFilter)
    }

    const { data, error } = await query
    if (error) {
      console.error("[admin-csv-support] fetch failed", error)
      setRows([])
      setProfilesByUserId({})
    } else {
      const list = (data as CsvSupportRequestRow[]) || []
      setRows(list)
      await loadProfilesForRows(list)
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
  }, [allowed, statusFilter])

  const filterLabel = useMemo(() => {
    if (statusFilter === "all") return "all requests"
    return csvSupportStatusLabel(statusFilter).toLowerCase()
  }, [statusFilter])

  function openDetail(row: CsvSupportRequestRow) {
    setSelected(row)
    const status = String(row.status || "new") as CsvSupportRequestStatus
    setDetailStatus(
      CSV_SUPPORT_STATUS_OPTIONS.some((o) => o.value === status) ? status : "new"
    )
  }

  async function handleDownload(row: CsvSupportRequestRow) {
    const path = row.csv_file_url?.trim()
    if (!path) {
      alert("No CSV file path on this request.")
      return
    }

    setDownloadingId(row.id)
    const result = await createCsvSupportSignedDownloadUrl(supabase, path)
    setDownloadingId(null)

    if ("error" in result) {
      alert(result.error)
      return
    }

    window.open(result.url, "_blank", "noopener,noreferrer")
  }

  async function handleSaveDetail() {
    if (!selected?.id) return
    setSavingDetail(true)

    const { error } = await supabase
      .from("csv_support_requests")
      .update({ status: detailStatus })
      .eq("id", selected.id)

    if (error) {
      console.error("[admin-csv-support] save failed", error)
      alert("Failed to update CSV support request.")
      setSavingDetail(false)
      return
    }

    setSelected(null)
    setSavingDetail(false)
    await fetchRows()
  }

  if (checking || !allowed) {
    return (
      <>
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-8 text-white">
          Checking admin access...
        </div>
      </>
    )
  }

  const tabBtn = (tab: StatusFilter, label: string) => (
    <button
      type="button"
      onClick={() => setStatusFilter(tab)}
      className={`rounded px-3 py-1.5 text-sm ${
        statusFilter === tab
          ? "bg-blue-500 text-white"
          : "bg-white/10 text-gray-200 hover:bg-white/20"
      }`}
    >
      {label}
    </button>
  )

  return (
    <>
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-4 text-gray-100 md:p-8">
        <div className="mx-auto max-w-6xl space-y-6">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h1 className="text-2xl font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent md:text-3xl">
              CSV Support
            </h1>
            <Link href="/admin" className="rounded bg-white/10 px-3 py-2 text-sm hover:bg-white/20">
              Back to Admin
            </Link>
          </div>

          <section className="rounded-xl border border-white/10 bg-white/5 p-5">
            <p className="mb-3 text-sm text-gray-400">
              Failed CSV import samples submitted by users. Download files from private storage and
              update review status.
            </p>
            <div className="flex flex-wrap gap-2">
              {tabBtn("new", "New")}
              {tabBtn("in_progress", "Reviewing")}
              {tabBtn("resolved", "Supported")}
              {tabBtn("closed", "Rejected")}
              {tabBtn("all", "All")}
            </div>

            {listLoading ? (
              <p className="mt-4 text-sm text-gray-300">Loading requests...</p>
            ) : !rows.length ? (
              <p className="mt-4 text-sm text-gray-300">No {filterLabel}.</p>
            ) : (
              <div className="mt-4 overflow-x-auto rounded-lg border border-white/10">
                <table className="min-w-full text-left text-sm">
                  <thead className="border-b border-white/10 bg-black/20 text-xs uppercase tracking-wide text-gray-400">
                    <tr>
                      <th className="px-3 py-2">Submitted</th>
                      <th className="px-3 py-2">User</th>
                      <th className="px-3 py-2">Broker</th>
                      <th className="px-3 py-2">Status</th>
                      <th className="px-3 py-2">File</th>
                      <th className="px-3 py-2">Notes</th>
                      <th className="px-3 py-2 text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((row) => {
                      const profile = row.user_id ? profilesByUserId[row.user_id] : null
                      return (
                        <tr
                          key={row.id}
                          className="border-b border-white/5 hover:bg-black/20"
                        >
                          <td className="whitespace-nowrap px-3 py-2 tabular-nums text-gray-300">
                            {row.created_at
                              ? new Date(row.created_at).toLocaleString()
                              : "—"}
                          </td>
                          <td className="max-w-[140px] truncate px-3 py-2">
                            <span className="text-white">
                              {formatCsvSupportUserLabel(row.user_id, profile)}
                            </span>
                            {profile?.is_beta_tester ? (
                              <span className="ml-1 rounded bg-amber-500/20 px-1.5 py-0.5 text-[10px] text-amber-200">
                                beta
                              </span>
                            ) : null}
                          </td>
                          <td className="max-w-[120px] truncate px-3 py-2 text-gray-200">
                            {row.broker_name || "—"}
                          </td>
                          <td className="px-3 py-2">
                            <span
                              className={`rounded px-2 py-0.5 text-xs ${statusBadgeClass(String(row.status))}`}
                            >
                              {csvSupportStatusLabel(row.status)}
                            </span>
                          </td>
                          <td className="max-w-[160px] truncate px-3 py-2 font-mono text-xs text-gray-400">
                            {csvStorageFilename(row.csv_file_url)}
                          </td>
                          <td className="max-w-[200px] truncate px-3 py-2 text-gray-400">
                            {previewText(row.notes, 80)}
                          </td>
                          <td className="whitespace-nowrap px-3 py-2 text-right">
                            <div className="flex justify-end gap-2">
                              <button
                                type="button"
                                onClick={() => void handleDownload(row)}
                                disabled={downloadingId === row.id || !row.csv_file_url}
                                className="rounded bg-blue-500/80 px-2.5 py-1 text-xs font-medium text-white hover:bg-blue-500 disabled:opacity-50"
                              >
                                {downloadingId === row.id ? "…" : "Download"}
                              </button>
                              <button
                                type="button"
                                onClick={() => openDetail(row)}
                                className="rounded bg-white/10 px-2.5 py-1 text-xs hover:bg-white/20"
                              >
                                Review
                              </button>
                            </div>
                          </td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
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
                  {selected.created_at
                    ? new Date(selected.created_at).toLocaleString()
                    : "—"}
                </p>
                <h3 className="mt-1 text-xl font-semibold">
                  {selected.broker_name || "Unknown broker"}
                </h3>
                <p className="mt-1 text-xs text-gray-400">
                  {formatCsvSupportUserLabel(
                    selected.user_id,
                    selected.user_id ? profilesByUserId[selected.user_id] : null
                  )}
                  {selected.user_id ? (
                    <span className="ml-2 font-mono text-gray-500">{selected.user_id}</span>
                  ) : null}
                </p>
              </div>
              <div className="flex shrink-0 items-center gap-2">
                <button
                  type="button"
                  onClick={() => void handleDownload(selected)}
                  disabled={downloadingId === selected.id || !selected.csv_file_url}
                  className="rounded bg-blue-500 px-3 py-2 text-sm font-semibold hover:bg-blue-600 disabled:opacity-60"
                >
                  {downloadingId === selected.id ? "Preparing…" : "Download CSV"}
                </button>
                <button
                  type="button"
                  onClick={() => void handleSaveDetail()}
                  disabled={savingDetail}
                  className="rounded bg-emerald-500 px-3 py-2 text-sm font-semibold hover:bg-emerald-600 disabled:opacity-60"
                >
                  {savingDetail ? "Saving..." : "Save"}
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
                <p className="text-xs text-gray-400">Storage path</p>
                <p className="mt-1 break-all font-mono text-sm text-gray-200">
                  {selected.csv_file_url || "—"}
                </p>
                <p className="mt-2 text-xs text-gray-500">
                  Filename: {csvStorageFilename(selected.csv_file_url)}
                </p>
              </div>

              <div className="rounded border border-white/10 bg-black/20 p-3">
                <p className="text-xs text-gray-400">Notes / diagnostics</p>
                <p className="mt-1 whitespace-pre-wrap text-sm text-gray-200">
                  {selected.notes || "—"}
                </p>
              </div>

              <div className="rounded border border-white/10 bg-black/20 p-3">
                <label className="text-xs text-gray-400">Status</label>
                <select
                  value={detailStatus}
                  onChange={(e) =>
                    setDetailStatus(e.target.value as CsvSupportRequestStatus)
                  }
                  className="mt-1 w-full rounded border border-white/10 bg-[#111827] p-2 text-sm md:max-w-xs"
                >
                  {CSV_SUPPORT_STATUS_OPTIONS.map((opt) => (
                    <option key={opt.value} value={opt.value}>
                      {opt.label}
                    </option>
                  ))}
                </select>
              </div>
            </div>
          </div>
        </div>
      ) : null}
    </>
  )
}
