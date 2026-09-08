"use client"

import Link from "next/link"
import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import CustomSelect from "@/app/components/CustomSelect"
import {
  type AdminContentReportEnrichment,
  type AdminReportProfileSummary,
  type AdminReportTargetPreview,
  getProfileSummary,
  getTargetPreview,
  hydrateAdminContentReports,
  listReportedSubjectLabel,
  listReporterLabel,
  logSupabaseError,
  moderationStatusLabel,
  profileDisplayName,
  profileHandle,
  resolveReportedUserId,
  suggestedBanReasonFromReport,
} from "@/lib/adminContentReports"
import { banUser, unbanUser } from "@/lib/adminModeration"
import { getCurrentAdminCheckResult } from "@/lib/adminUsers"
import { SELECT_TRIGGER_CLASS } from "@/lib/accountDropdownStyles"
import {
  CONTENT_REPORT_STATUSES,
  contentReportReasonLabel,
  contentReportStatusLabel,
  contentReportTargetLabel,
  type ContentReportRow,
  type ContentReportStatus,
} from "@/lib/contentReports"
import { profilePath } from "@/lib/profileRoutes"
import { supabase } from "@/lib/supabaseClient"
import type { TableUpdate } from "@/lib/supabaseTypes"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"

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

function ProfileSummaryCard({
  title,
  profile,
  enrichment,
  userId,
}: {
  title: string
  profile: AdminReportProfileSummary | null
  enrichment: AdminContentReportEnrichment
  userId: string | null
}) {
  const resolved =
    profile ?? (userId ? getProfileSummary(enrichment, userId) : null)

  return (
    <div className="rounded-lg border border-white/10 bg-black/20 p-4">
      <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">
        {title}
      </h3>
      {resolved ? (
        <div className="mt-3 flex items-start gap-3">
          <ProfileAvatarImg
            src={resolved.avatar_url}
            alt={profileDisplayName(resolved)}
            className="h-11 w-11 shrink-0"
          />
          <div className="min-w-0 flex-1">
            <p className="font-medium text-white">{profileDisplayName(resolved)}</p>
            <p className="text-sm text-gray-400">{profileHandle(resolved)}</p>
            {"is_banned" in resolved ? (
              <p
                className={`mt-1 text-xs ${resolved.is_banned ? "text-red-300" : "text-emerald-300"}`}
              >
                {moderationStatusLabel(resolved)}
              </p>
            ) : null}
            <Link
              href={profilePath(resolved)}
              className="mt-2 inline-block text-sm text-blue-300 hover:text-blue-200"
            >
              View Profile
            </Link>
          </div>
        </div>
      ) : (
        <p className="mt-2 text-sm text-gray-500">Profile unavailable</p>
      )}
    </div>
  )
}

function TargetPreviewCard({
  preview,
  targetTypeLabel,
}: {
  preview: AdminReportTargetPreview
  targetTypeLabel: string
}) {
  const sectionTitle =
    preview.targetType === "user" ? "Reported profile" : "Reported content"

  return (
    <div className="rounded-lg border border-white/10 bg-black/20 p-4">
      <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">
        {sectionTitle}
      </h3>
      <p className="mt-2 text-xs text-gray-500">{targetTypeLabel}</p>
      <p className="mt-1 font-medium text-white">{preview.headline}</p>
      {preview.subline ? (
        <p className="mt-1 text-sm text-gray-400">{preview.subline}</p>
      ) : null}
      {preview.unavailable ? (
        <p className="mt-2 text-xs text-amber-300/90">
          Original content may have been deleted.
        </p>
      ) : null}
      {preview.href ? (
        <Link
          href={preview.href}
          className="mt-3 inline-block text-sm text-blue-300 hover:text-blue-200"
        >
          {preview.viewLabel}
        </Link>
      ) : null}
    </div>
  )
}

export default function AdminContentReportsPage() {
  const router = useRouter()
  const [checking, setChecking] = useState(true)
  const [allowed, setAllowed] = useState(false)
  const [adminUserId, setAdminUserId] = useState<string | null>(null)
  const [rows, setRows] = useState<ContentReportRow[]>([])
  const [enrichment, setEnrichment] = useState<AdminContentReportEnrichment>({
    profiles: {},
    targets: {},
  })
  const [listLoading, setListLoading] = useState(false)
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("open")
  const [selected, setSelected] = useState<ContentReportRow | null>(null)
  const [detailStatus, setDetailStatus] = useState<ContentReportStatus>("open")
  const [savingDetail, setSavingDetail] = useState(false)
  const [showTechnicalDetails, setShowTechnicalDetails] = useState(false)
  const [banReason, setBanReason] = useState("")
  const [moderationBusy, setModerationBusy] = useState(false)

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
      logSupabaseError("[admin-content-reports] fetch failed", error)
      setRows([])
      setEnrichment({ profiles: {}, targets: {} })
      setListLoading(false)
      return
    }

    const reportRows = (data ?? []) as ContentReportRow[]
    setRows(reportRows)

    try {
      const nextEnrichment = await hydrateAdminContentReports(supabase, reportRows)
      setEnrichment(nextEnrichment)
    } catch (err) {
      console.error("[admin-content-reports] enrichment failed", err)
      setEnrichment({ profiles: {}, targets: {} })
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
        setAdminUserId(check.userId)
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

  const selectedReportedUserId = selected ? resolveReportedUserId(selected) : null
  const selectedReportedProfile = selectedReportedUserId
    ? getProfileSummary(enrichment, selectedReportedUserId)
    : null

  const selectedTargetPreview = selected
    ? getTargetPreview(enrichment, selected)
    : null

  function openDetail(row: ContentReportRow) {
    setSelected(row)
    setDetailStatus(row.status)
    setShowTechnicalDetails(false)
    setBanReason(suggestedBanReasonFromReport(row))
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
      alert(toUserFacingErrorMessage(error))
      setSavingDetail(false)
      return
    }

    setSelected(null)
    setSavingDetail(false)
    void fetchRows()
  }

  async function handleBanReportedUser() {
    if (!selected || !adminUserId || !selectedReportedUserId) return
    if (!banReason.trim()) {
      alert("Please enter a ban reason.")
      return
    }
    const handle = profileHandle(selectedReportedProfile)
    if (!window.confirm(`Ban ${handle}? This uses the platform ban system.`)) return

    setModerationBusy(true)
    const { error } = await banUser(supabase, {
      adminUserId,
      targetUserId: selectedReportedUserId,
      reason: banReason,
    })
    setModerationBusy(false)

    if (error) {
      alert(toUserFacingErrorMessage(error))
      return
    }

    await fetchRows()
    const updatedProfile: AdminReportProfileSummary = selectedReportedProfile
      ? {
          ...selectedReportedProfile,
          is_banned: true,
          banned_reason: banReason.trim(),
          banned_at: new Date().toISOString(),
        }
      : {
          id: selectedReportedUserId,
          username: null,
          name: null,
          avatar_url: null,
          is_banned: true,
          banned_reason: banReason.trim(),
          banned_at: new Date().toISOString(),
        }
    setEnrichment((prev) => ({
      ...prev,
      profiles: { ...prev.profiles, [selectedReportedUserId]: updatedProfile },
    }))
  }

  async function handleUnbanReportedUser() {
    if (!selected || !adminUserId || !selectedReportedUserId) return
    const handle = profileHandle(selectedReportedProfile)
    if (!window.confirm(`Unban ${handle}?`)) return

    setModerationBusy(true)
    const { error } = await unbanUser(supabase, {
      adminUserId,
      targetUserId: selectedReportedUserId,
    })
    setModerationBusy(false)

    if (error) {
      alert(toUserFacingErrorMessage(error))
      return
    }

    setBanReason("")
    await fetchRows()
    const updatedProfile: AdminReportProfileSummary = selectedReportedProfile
      ? {
          ...selectedReportedProfile,
          is_banned: false,
          banned_reason: null,
          banned_at: null,
        }
      : {
          id: selectedReportedUserId,
          username: null,
          name: null,
          avatar_url: null,
          is_banned: false,
          banned_reason: null,
          banned_at: null,
        }
    setEnrichment((prev) => ({
      ...prev,
      profiles: { ...prev.profiles, [selectedReportedUserId]: updatedProfile },
    }))
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
                <th className="px-4 py-3 font-medium">Type</th>
                <th className="px-4 py-3 font-medium">Reported Content/User</th>
                <th className="px-4 py-3 font-medium">Reported By</th>
                <th className="px-4 py-3 font-medium">Reason</th>
                <th className="px-4 py-3 font-medium">Status</th>
                <th className="px-4 py-3 font-medium">Created</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr
                  key={row.id}
                  className="border-t border-white/10 hover:bg-white/5 cursor-pointer"
                  onClick={() => openDetail(row)}
                >
                  <td className="px-4 py-3 whitespace-nowrap">
                    {contentReportTargetLabel(row.target_type)}
                  </td>
                  <td className="px-4 py-3 max-w-[240px]">
                    <p className="truncate text-gray-200">
                      {listReportedSubjectLabel(row, enrichment)}
                    </p>
                    <p className="truncate text-xs text-gray-500">
                      {getTargetPreview(enrichment, row).headline}
                    </p>
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap text-gray-300">
                    {listReporterLabel(row, enrichment)}
                  </td>
                  <td className="px-4 py-3">
                    {contentReportReasonLabel(row.reason)}
                  </td>
                  <td className="px-4 py-3">
                    <span
                      className={`rounded px-2 py-0.5 text-xs font-semibold ${statusBadgeClass(row.status)}`}
                    >
                      {contentReportStatusLabel(row.status)}
                    </span>
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap text-gray-400">
                    {new Date(row.created_at).toLocaleString()}
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

      {selected && selectedTargetPreview ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4">
          <div className="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-xl border border-white/15 bg-[#12121a] p-6 shadow-xl">
            <div className="flex items-start justify-between gap-4">
              <h2 className="text-lg font-semibold text-white">Report detail</h2>
              <button
                type="button"
                className="text-sm text-gray-400 hover:text-gray-200"
                onClick={() => setSelected(null)}
              >
                Close
              </button>
            </div>

            <div className="mt-6 space-y-4">
              <section className="rounded-lg border border-white/10 bg-black/20 p-4">
                <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">
                  Report
                </h3>
                <dl className="mt-3 grid gap-3 text-sm sm:grid-cols-2">
                  <div>
                    <dt className="text-gray-500">Type</dt>
                    <dd>{contentReportTargetLabel(selected.target_type)}</dd>
                  </div>
                  <div>
                    <dt className="text-gray-500">Reason</dt>
                    <dd>{contentReportReasonLabel(selected.reason)}</dd>
                  </div>
                  <div className="sm:col-span-2">
                    <dt className="text-gray-500">Details</dt>
                    <dd className="text-gray-200 whitespace-pre-wrap">
                      {previewText(selected.details, 2000)}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-gray-500">Created</dt>
                    <dd>{new Date(selected.created_at).toLocaleString()}</dd>
                  </div>
                  <div>
                    <dt className="text-gray-500">Status</dt>
                    <dd>{contentReportStatusLabel(selected.status)}</dd>
                  </div>
                </dl>
              </section>

              <TargetPreviewCard
                preview={selectedTargetPreview}
                targetTypeLabel={contentReportTargetLabel(selected.target_type)}
              />

              {selectedReportedUserId ? (
                <ProfileSummaryCard
                  title="Reported user"
                  profile={selectedReportedProfile}
                  enrichment={enrichment}
                  userId={selectedReportedUserId}
                />
              ) : null}

              <ProfileSummaryCard
                title="Reporter"
                profile={getProfileSummary(enrichment, selected.reporter_user_id)}
                enrichment={enrichment}
                userId={selected.reporter_user_id}
              />

              {selectedReportedUserId ? (
                <section className="rounded-lg border border-white/10 bg-black/30 p-4">
                  <h3 className="text-sm font-semibold text-gray-200">
                    Moderation actions
                  </h3>
                  <p className="mt-1 text-xs text-gray-400">
                    Uses the existing platform ban system from Admin → Users.
                  </p>
                  {selectedReportedProfile?.is_banned ? (
                    <>
                      <p className="mt-2 text-xs text-red-300">
                        This user is banned
                        {selectedReportedProfile.banned_reason
                          ? `: ${selectedReportedProfile.banned_reason}`
                          : "."}
                      </p>
                      <div className="mt-3 flex flex-wrap gap-2">
                        <Link
                          href={profilePath(selectedReportedProfile)}
                          className="rounded border border-white/15 px-3 py-2 text-sm hover:bg-white/5"
                        >
                          View Profile
                        </Link>
                        <Link
                          href="/admin/users"
                          className="rounded border border-white/15 px-3 py-2 text-sm hover:bg-white/5"
                        >
                          Open Users admin
                        </Link>
                        <button
                          type="button"
                          disabled={moderationBusy}
                          onClick={() => void handleUnbanReportedUser()}
                          className="rounded bg-blue-600 px-4 py-2 text-sm font-semibold hover:bg-blue-500 disabled:opacity-50"
                        >
                          Unban user
                        </button>
                      </div>
                    </>
                  ) : (
                    <>
                      <label className="mt-3 block text-xs text-gray-400">
                        Ban reason (required)
                        <textarea
                          value={banReason}
                          onChange={(e) => setBanReason(e.target.value)}
                          rows={3}
                          className="mt-1 w-full rounded border border-white/10 bg-[#111827] p-2 text-sm text-white"
                          placeholder="Explain why this account is being banned…"
                        />
                      </label>
                      <div className="mt-3 flex flex-wrap gap-2">
                        {selectedReportedProfile ? (
                          <Link
                            href={profilePath(selectedReportedProfile)}
                            className="rounded border border-white/15 px-3 py-2 text-sm hover:bg-white/5"
                          >
                            View Profile
                          </Link>
                        ) : null}
                        <Link
                          href="/admin/users"
                          className="rounded border border-white/15 px-3 py-2 text-sm hover:bg-white/5"
                        >
                          Open Users admin
                        </Link>
                        <button
                          type="button"
                          disabled={moderationBusy}
                          onClick={() => void handleBanReportedUser()}
                          className="rounded bg-red-600 px-4 py-2 text-sm font-semibold hover:bg-red-500 disabled:opacity-50"
                        >
                          Ban user
                        </button>
                      </div>
                    </>
                  )}
                </section>
              ) : null}

              <section className="rounded-lg border border-white/10 bg-black/20 p-4">
                <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">
                  Report status
                </h3>
                <div className="mt-3 space-y-2">
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
              </section>

              <section className="rounded-lg border border-white/10 bg-black/10 p-4">
                <button
                  type="button"
                  className="text-xs font-semibold uppercase tracking-wide text-gray-500 hover:text-gray-300"
                  onClick={() => setShowTechnicalDetails((v) => !v)}
                >
                  Technical details {showTechnicalDetails ? "▾" : "▸"}
                </button>
                {showTechnicalDetails ? (
                  <dl className="mt-3 space-y-2 text-xs text-gray-500">
                    <div>
                      <dt>Report ID</dt>
                      <dd className="font-mono break-all">{selected.id}</dd>
                    </div>
                    <div>
                      <dt>Target ID</dt>
                      <dd className="font-mono break-all">{selected.target_id}</dd>
                    </div>
                    <div>
                      <dt>Reported user ID</dt>
                      <dd className="font-mono break-all">
                        {selected.reported_user_id ?? "—"}
                      </dd>
                    </div>
                    <div>
                      <dt>Reporter user ID</dt>
                      <dd className="font-mono break-all">
                        {selected.reporter_user_id}
                      </dd>
                    </div>
                  </dl>
                ) : null}
              </section>
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
