"use client"

import Link from "next/link"
import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { getCurrentAdminCheckResult } from "@/lib/adminUsers"
import {
  CONTENT_REPORT_STATUSES,
  contentReportReasonLabel,
  contentReportStatusLabel,
  contentReportTargetLabel,
  type ContentReportReason,
  type ContentReportRow,
  type ContentReportStatus,
} from "@/lib/contentReports"
import { supabase } from "@/lib/supabaseClient"
import CustomSelect from "@/app/components/CustomSelect"
import { SELECT_TRIGGER_CLASS } from "@/lib/accountDropdownStyles"
import type { TableUpdate } from "@/lib/supabaseTypes"

type StatusFilter = "all" | ContentReportStatus

function previewText(text: string | null | undefined, max = 120) {
  const t = (text || "").replace(/\s+/g, " ").trim()
  if (!t) return "—"
  return t.length > max ? `${t.slice(0, max)}…` : t
}

function statusBadgeClass(status: ContentReportStatus) {
  switch (status) {
    case "open":
      return "bg-red-500/25 text-red-100"
    case "reviewing":
      return "bg-amber-500/20 text-amber-100"
    case "resolved":
      return "bg-emerald-500/20 text-emerald-100"
    case "dismissed":
      return "bg-white/10 text-gray-300"
    default:
      return "bg-white/10 text-gray-200"
  }
}

export default function AdminContentReportsPage() {
  const router = useRouter()
  const [checking, setChecking] = useState(true)
  const [allowed, setAllowed] = useState(false)
  const [rows, setRows] = useState<ContentReportRow[]>([])
  const [listLoading, setListLoading] = useState(false)
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("open")
  const [selected, setSelected] = useState<ContentReportRow | null>(null)
  const [detailStatus, setDetailStatus] = useState<ContentReportStatus>("open")
  const [savingDetail, setSavingDetail] = useState(false)

  async function fetchRows() {
    if (!allowed) return
    setListLoading(true)

    let query = supabase
      .from("content_reports")
      .select(
        "id, reporter_user_id, target_type, target_id, reported_user_id, reason, details, status, created_at, reviewed_at, reviewed_by"
      )
      .order("created_at", { ascending: false })

    if (statusFilter !== "all") {
      query = query.eq("status", statusFilter)
    }

    const { data, error } = await query
    if (error) {
      console.error("[admin-content-reports] fetch failed", error)
      setRows([])
    } else {
      setRows((data as ContentReportRow[]) || [])
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

  const filteredCountLabel = useMemo(() => {
    return statusFilter === "all" ? "all reports" : statusFilter.replace("_", " ")
  }, [statusFilter])

  function openDetail(row: ContentReportRow) {
    setSelected(row)
    setDetailStatus(row.status)
  }

  async function saveDetailStatus() {
    if (!selected || !allowed) return
    setSavingDetail(true)
    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user?.id) {
      setSavingDetail(false)
      return
    }

    const patch: TableUpdate<"content_reports"> = {
      status: detailStatus,
      reviewed_at: new Date().toISOString(),
      reviewed_by: user.id,
    }

    const { error } = await supabase
      .from("content_reports")
      .update(patch)
      .eq("id", selected.id)

    if (error) {
      console.error("[admin-content-reports] update failed", error)
      setSavingDetail(false)
      return
    }

    setSelected(null)
    setSavingDetail(false)
    void fetchRows()
  }

  if (checking) {
    return (
      <div className="min-h-screen bg-[#0a0a0f] text-white p-8">
        <p className="text-gray-400">Checking admin access…</p>
      </div>
    )
  }

  if (!allowed) return null

  return (
    <div className="min-h-screen bg-[#0a0a0f] text-white">
      <div className="mx-auto max-w-6xl px-4 py-8 space-y-6">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div>
            <Link
              href="/admin"
              className="text-sm text-blue-300 hover:text-blue-200"
            >
              ← Admin
            </Link>
            <h1 className="mt-2 text-2xl font-bold text-blue-300">
              Content Reports
            </h1>
            <p className="mt-1 text-sm text-gray-400">
              UGC moderation queue from in-app reports.
            </p>
          </div>
          <div className="flex items-center gap-3">
            <CustomSelect
              value={statusFilter}
              onChange={(v) => setStatusFilter(v as StatusFilter)}
              options={[
                { value: "all", label: "All statuses" },
                ...CONTENT_REPORT_STATUSES.map((s) => ({
                  value: s,
                  label: contentReportStatusLabel(s),
                })),
              ]}
              triggerClassName={SELECT_TRIGGER_CLASS}
            />
            <button
              type="button"
              onClick={() => void fetchRows()}
              className="rounded-lg border border-white/15 px-3 py-2 text-sm hover:bg-white/5"
            >
              Refresh
            </button>
          </div>
        </div>

        <p className="text-sm text-gray-500">
          Showing {rows.length} {filteredCountLabel}
          {listLoading ? " · loading…" : ""}
        </p>

        <div className="overflow-x-auto rounded-xl border border-white/10">
          <table className="min-w-full text-left text-sm">
            <thead className="bg-white/5 text-gray-300">
              <tr>
                <th className="px-4 py-3 font-medium">Created</th>
                <th className="px-4 py-3 font-medium">Type</th>
                <th className="px-4 py-3 font-medium">Reason</th>
                <th className="px-4 py-3 font-medium">Target</th>
                <th className="px-4 py-3 font-medium">Reporter</th>
                <th className="px-4 py-3 font-medium">Status</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr
                  key={row.id}
                  className="border-t border-white/10 hover:bg-white/5 cursor-pointer"
                  onClick={() => openDetail(row)}
                >
                  <td className="px-4 py-3 whitespace-nowrap text-gray-300">
                    {new Date(row.created_at).toLocaleString()}
                  </td>
                  <td className="px-4 py-3">
                    {contentReportTargetLabel(row.target_type)}
                  </td>
                  <td className="px-4 py-3">
                    {contentReportReasonLabel(row.reason)}
                  </td>
                  <td className="px-4 py-3 font-mono text-xs text-gray-400 max-w-[200px] truncate">
                    {row.target_id}
                  </td>
                  <td className="px-4 py-3 font-mono text-xs text-gray-400 max-w-[140px] truncate">
                    {row.reporter_user_id}
                  </td>
                  <td className="px-4 py-3">
                    <span
                      className={`rounded px-2 py-0.5 text-xs font-semibold ${statusBadgeClass(row.status)}`}
                    >
                      {contentReportStatusLabel(row.status)}
                    </span>
                  </td>
                </tr>
              ))}
              {!listLoading && rows.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-4 py-8 text-center text-gray-500">
                    No reports in this filter.
                  </td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>
      </div>

      {selected ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4">
          <div className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-xl border border-white/15 bg-[#12121a] p-6 shadow-xl">
            <h2 className="text-lg font-semibold text-white">Report detail</h2>
            <dl className="mt-4 space-y-3 text-sm">
              <div>
                <dt className="text-gray-500">Type</dt>
                <dd>{contentReportTargetLabel(selected.target_type)}</dd>
              </div>
              <div>
                <dt className="text-gray-500">Reason</dt>
                <dd>{contentReportReasonLabel(selected.reason)}</dd>
              </div>
              <div>
                <dt className="text-gray-500">Details</dt>
                <dd className="text-gray-200 whitespace-pre-wrap">
                  {previewText(selected.details, 2000)}
                </dd>
              </div>
              <div>
                <dt className="text-gray-500">Target ID</dt>
                <dd className="font-mono text-xs break-all">{selected.target_id}</dd>
              </div>
              <div>
                <dt className="text-gray-500">Reported user</dt>
                <dd className="font-mono text-xs break-all">
                  {selected.reported_user_id ?? "—"}
                </dd>
              </div>
              <div>
                <dt className="text-gray-500">Reporter</dt>
                <dd className="font-mono text-xs break-all">
                  {selected.reporter_user_id}
                </dd>
              </div>
              <div>
                <dt className="text-gray-500">Created</dt>
                <dd>{new Date(selected.created_at).toLocaleString()}</dd>
              </div>
            </dl>

            <div className="mt-6 space-y-2">
              <label className="text-sm text-gray-400">Status</label>
              <CustomSelect
                value={detailStatus}
                onChange={(v) => setDetailStatus(v as ContentReportStatus)}
                options={CONTENT_REPORT_STATUSES.map((s) => ({
                  value: s,
                  label: contentReportStatusLabel(s),
                }))}
                triggerClassName={SELECT_TRIGGER_CLASS}
              />
            </div>

            <div className="mt-6 flex justify-end gap-3">
              <button
                type="button"
                className="rounded-lg border border-white/15 px-4 py-2 text-sm"
                onClick={() => setSelected(null)}
              >
                Cancel
              </button>
              <button
                type="button"
                disabled={savingDetail}
                className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold disabled:opacity-50"
                onClick={() => void saveDetailStatus()}
              >
                {savingDetail ? "Saving…" : "Save status"}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  )
}
