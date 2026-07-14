"use client"

import Link from "next/link"
import { useCallback, useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import { getCurrentAdminCheckResult } from "@/lib/adminUsers"
import { banUser, unbanUser } from "@/lib/adminModeration"
import {
  type AdminUserActivityCounts,
  type AdminUserListRow,
  fetchAdminUserDirectory,
  fetchUserActivityCounts,
} from "@/lib/adminUsersDirectory"
import { isProActive } from "@/lib/subscription"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"
import { supabase } from "@/lib/supabaseClient"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"
import CustomSelect from "@/app/components/CustomSelect"
import { SELECT_TRIGGER_CLASS } from "@/lib/accountDropdownStyles"

const PAGE_SIZE = 20

/** TEMPORARY BETA CLEANUP TOOL — bulk multi-select delete; remove after launch. */
type BulkDeleteUserRef = { id: string; username: string }
type BulkDeleteOutcome = {
  deleted: BulkDeleteUserRef[]
  skipped: Array<BulkDeleteUserRef & { reason: string }>
  failed: Array<BulkDeleteUserRef & { message: string; step?: string | null; table?: string | null }>
}

type AdminDeleteApiError = {
  message: string
  step?: string | null
  table?: string | null
  code?: string
}

async function postAdminUserDelete(
  userId: string
): Promise<{ ok: true } | { ok: false; error: AdminDeleteApiError }> {
  const res = await fetch(`/api/admin/users/${userId}/delete`, {
    method: "POST",
    credentials: "include",
    headers: {
      "Content-Type": "application/json",
      ...(await supabaseBearerHeaders()),
    },
    body: JSON.stringify({ confirmation: "DELETE" }),
  })
  const data = (await res.json()) as {
    error?: string
    step?: string | null
    table?: string | null
    message?: string
    code?: string
  }
  if (!res.ok) {
    return {
      ok: false,
      error: {
        message: data.message ?? data.error ?? "Delete failed",
        step: data.step ?? null,
        table: data.table ?? null,
        code: data.code,
      },
    }
  }
  return { ok: true }
}

function bulkUserLabel(row: Pick<AdminUserListRow, "id" | "username">) {
  return row.username ? `@${row.username}` : row.id
}

export default function AdminUsersPage() {
  const router = useRouter()
  const [checking, setChecking] = useState(true)
  const [allowed, setAllowed] = useState(false)
  const [adminUserId, setAdminUserId] = useState<string | null>(null)

  const [search, setSearch] = useState("")
  const [debouncedSearch, setDebouncedSearch] = useState("")
  const [bannedFilter, setBannedFilter] = useState<"all" | "banned" | "active">("all")
  const [proFilter, setProFilter] = useState<"all" | "pro" | "non_pro">("all")
  const [privacyFilter, setPrivacyFilter] = useState<"all" | "private" | "public">("all")
  const [offset, setOffset] = useState(0)
  const [rows, setRows] = useState<AdminUserListRow[]>([])
  const [total, setTotal] = useState(0)
  const [listLoading, setListLoading] = useState(false)
  const [listError, setListError] = useState<string | null>(null)

  const [selected, setSelected] = useState<AdminUserListRow | null>(null)
  const [counts, setCounts] = useState<AdminUserActivityCounts | null>(null)
  const [countsError, setCountsError] = useState<string | null>(null)
  const [countsLoading, setCountsLoading] = useState(false)
  const [banReason, setBanReason] = useState("")
  const [moderationBusy, setModerationBusy] = useState(false)
  const [deleteView, setDeleteView] = useState(false)
  const [deletePreview, setDeletePreview] = useState<Record<string, unknown> | null>(null)
  const [deletePreviewLoading, setDeletePreviewLoading] = useState(false)
  const [deleteConfirm, setDeleteConfirm] = useState("")
  const [deleteBusy, setDeleteBusy] = useState(false)
  const [deleteError, setDeleteError] = useState<{
    step?: string | null
    table?: string | null
    message: string
  } | null>(null)

  /** TEMPORARY BETA CLEANUP TOOL */
  const [adminUserIds, setAdminUserIds] = useState<Set<string>>(new Set())
  const [bulkSelectedIds, setBulkSelectedIds] = useState<Set<string>>(new Set())
  const [bulkDeleteModalOpen, setBulkDeleteModalOpen] = useState(false)
  const [bulkDeleteConfirm, setBulkDeleteConfirm] = useState("")
  const [bulkDeleteBusy, setBulkDeleteBusy] = useState(false)
  const [bulkDeleteOutcome, setBulkDeleteOutcome] = useState<BulkDeleteOutcome | null>(null)

  useEffect(() => {
    const t = window.setTimeout(() => setDebouncedSearch(search), 300)
    return () => window.clearTimeout(t)
  }, [search])

  useEffect(() => {
    setOffset(0)
  }, [debouncedSearch, bannedFilter, proFilter, privacyFilter])

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
        setAdminUserId(check.userId)
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
      const { data } = await supabase.from("admin_users").select("user_id")
      if (cancelled) return
      setAdminUserIds(new Set((data ?? []).map((r) => String(r.user_id))))
    })()
    return () => {
      cancelled = true
    }
  }, [allowed])

  const isBulkDeletable = useCallback(
    (row: AdminUserListRow) => {
      if (!adminUserId) return false
      if (row.id === adminUserId) return false
      if (adminUserIds.has(row.id)) return false
      return true
    },
    [adminUserId, adminUserIds]
  )

  const deletableRowsOnPage = rows.filter(isBulkDeletable)
  const bulkSelectedCount = bulkSelectedIds.size
  const allDeletableOnPageSelected =
    deletableRowsOnPage.length > 0 &&
    deletableRowsOnPage.every((row) => bulkSelectedIds.has(row.id))
  const someDeletableOnPageSelected =
    deletableRowsOnPage.some((row) => bulkSelectedIds.has(row.id)) &&
    !allDeletableOnPageSelected

  function toggleBulkSelectRow(row: AdminUserListRow) {
    if (!isBulkDeletable(row)) return
    setBulkSelectedIds((prev) => {
      const next = new Set(prev)
      if (next.has(row.id)) next.delete(row.id)
      else next.add(row.id)
      return next
    })
  }

  function toggleBulkSelectAllOnPage() {
    if (allDeletableOnPageSelected) {
      setBulkSelectedIds((prev) => {
        const next = new Set(prev)
        for (const row of deletableRowsOnPage) next.delete(row.id)
        return next
      })
      return
    }
    setBulkSelectedIds((prev) => {
      const next = new Set(prev)
      for (const row of deletableRowsOnPage) next.add(row.id)
      return next
    })
  }

  function openBulkDeleteModal() {
    if (bulkSelectedCount === 0) return
    setBulkDeleteConfirm("")
    setBulkDeleteOutcome(null)
    setBulkDeleteModalOpen(true)
  }

  function closeBulkDeleteModal() {
    if (bulkDeleteBusy) return
    setBulkDeleteModalOpen(false)
    setBulkDeleteConfirm("")
  }

  function resolveBulkSelectedRows(): AdminUserListRow[] {
    const byId = new Map(rows.map((r) => [r.id, r]))
    return [...bulkSelectedIds].map(
      (id) =>
        byId.get(id) ?? {
          id,
          username: "",
          name: "",
          email: "",
          avatar_url: null,
          created_at: "",
          is_private: false,
          is_pro: false,
          subscription_status: "",
          referral_code: "",
          is_banned: false,
          banned_reason: null,
          banned_at: null,
          is_beta_tester: false,
          full_count: 0,
        }
    )
  }

  const bulkModalRows = bulkDeleteModalOpen ? resolveBulkSelectedRows() : []

  const loadDirectory = useCallback(async () => {
    if (!allowed) return
    setListLoading(true)
    setListError(null)
    const { rows: r, total: t, error } = await fetchAdminUserDirectory(supabase, {
      search: debouncedSearch,
      banned: bannedFilter,
      pro: proFilter,
      privacy: privacyFilter,
      limit: PAGE_SIZE,
      offset,
    })
    if (error) {
      setListError(toUserFacingErrorMessage(error))
      setRows([])
      setTotal(0)
    } else {
      setRows(r)
      setTotal(t)
    }
    setListLoading(false)
  }, [allowed, debouncedSearch, bannedFilter, proFilter, privacyFilter, offset])

  useEffect(() => {
    void loadDirectory()
  }, [loadDirectory])

  async function handleBulkDeleteSelected() {
    if (bulkDeleteConfirm !== "DELETE" || bulkSelectedCount === 0) return

    const selectedRows = resolveBulkSelectedRows()
    const outcome: BulkDeleteOutcome = { deleted: [], skipped: [], failed: [] }

    setBulkDeleteBusy(true)
    setBulkDeleteOutcome(null)

    for (const row of selectedRows) {
      const label = bulkUserLabel(row)
      if (!isBulkDeletable(row)) {
        const reason =
          row.id === adminUserId
            ? "You cannot delete your own account."
            : adminUserIds.has(row.id)
              ? "Admin accounts cannot be deleted."
              : "Not eligible for deletion."
        outcome.skipped.push({ id: row.id, username: label, reason })
        continue
      }

      const result = await postAdminUserDelete(row.id)
      if (result.ok) {
        outcome.deleted.push({ id: row.id, username: label })
        setBulkSelectedIds((prev) => {
          const next = new Set(prev)
          next.delete(row.id)
          return next
        })
      } else if (
        result.error.code === "SELF_DELETE" ||
        result.error.code === "ADMIN_TARGET"
      ) {
        outcome.skipped.push({
          id: row.id,
          username: label,
          reason: toUserFacingErrorMessage(result.error),
        })
      } else {
        outcome.failed.push({
          id: row.id,
          username: label,
          message: toUserFacingErrorMessage(result.error),
          step: result.error.step,
          table: result.error.table,
        })
      }
    }

    setBulkDeleteOutcome(outcome)
    setBulkDeleteBusy(false)
    await loadDirectory()
  }

  useEffect(() => {
    if (!selected?.id) {
      setCounts(null)
      setCountsError(null)
      return
    }
    let cancelled = false
    setCountsLoading(true)
    setCountsError(null)
    void (async () => {
      const { data, error } = await fetchUserActivityCounts(supabase, selected.id)
      if (cancelled) return
      if (error) {
        setCountsError(toUserFacingErrorMessage(error))
        setCounts(data)
      } else {
        setCounts(data)
        setCountsError(null)
      }
      setCountsLoading(false)
    })()
    return () => {
      cancelled = true
    }
  }, [selected?.id])

  function openRow(row: AdminUserListRow) {
    setSelected(row)
    setBanReason(row.banned_reason || "")
    setDeleteView(false)
    setDeletePreview(null)
    setDeleteConfirm("")
    setDeleteError(null)
  }

  async function openDeleteView() {
    if (!selected) return
    setDeleteView(true)
    setDeleteConfirm("")
    setDeleteError(null)
    setDeletePreviewLoading(true)
    try {
      const res = await fetch(`/api/admin/users/${selected.id}/delete-preview`, {
        credentials: "include",
        headers: {
          ...(await supabaseBearerHeaders()),
        },
      })
      const data = (await res.json()) as { preview?: Record<string, unknown>; error?: string }
      if (!res.ok) {
        throw new Error(data.error || "Failed to load deletion preview")
      }
      setDeletePreview(data.preview ?? null)
    } catch (err) {
      setDeleteError({
        message: toUserFacingErrorMessage(
          err,
          "Failed to load deletion preview"
        ),
      })
      setDeletePreview(null)
    } finally {
      setDeletePreviewLoading(false)
    }
  }

  async function handleDeleteUser() {
    if (!selected || deleteConfirm !== "DELETE") return
    if (!window.confirm(`Permanently delete @${selected.username || selected.id}? This cannot be undone.`)) {
      return
    }

    setDeleteBusy(true)
    setDeleteError(null)
    try {
      const result = await postAdminUserDelete(selected.id)
      if (!result.ok) {
        console.error("[admin-users] delete failed", result.error)
        setDeleteError({
          message: toUserFacingErrorMessage(result.error),
        })
        return
      }
      setSelected(null)
      setDeleteView(false)
      setDeletePreview(null)
      setDeleteConfirm("")
      await loadDirectory()
    } catch (err) {
      setDeleteError({
        message: toUserFacingErrorMessage(err, "Delete failed"),
      })
    } finally {
      setDeleteBusy(false)
    }
  }

  const deleteBlockedReason =
    selected && adminUserId && selected.id === adminUserId
      ? "You cannot delete your own account."
      : null

  async function handleBan() {
    if (!selected || !adminUserId) return
    if (!banReason.trim()) {
      alert("Please enter a ban reason.")
      return
    }
    if (!window.confirm(`Ban user @${selected.username || selected.id}?`)) return
    setModerationBusy(true)
    const { error } = await banUser(supabase, {
      adminUserId,
      targetUserId: selected.id,
      reason: banReason,
    })
    setModerationBusy(false)
    if (error) {
      alert(toUserFacingErrorMessage(error))
      return
    }
    setSelected({ ...selected, is_banned: true, banned_reason: banReason.trim(), banned_at: new Date().toISOString() })
    await loadDirectory()
  }

  async function handleUnban() {
    if (!selected || !adminUserId) return
    if (!window.confirm(`Unban user @${selected.username || selected.id}?`)) return
    setModerationBusy(true)
    const { error } = await unbanUser(supabase, { adminUserId, targetUserId: selected.id })
    setModerationBusy(false)
    if (error) {
      alert(toUserFacingErrorMessage(error))
      return
    }
    setBanReason("")
    setSelected({
      ...selected,
      is_banned: false,
      banned_reason: null,
      banned_at: null,
    })
    await loadDirectory()
  }

  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE))
  const currentPage = Math.min(totalPages, Math.floor(offset / PAGE_SIZE) + 1)
  const rangeStart = total === 0 ? 0 : offset + 1
  const rangeEnd = total === 0 ? 0 : Math.min(offset + rows.length, total)
  const canPrev = offset > 0
  const canNext = offset + PAGE_SIZE < total

  function goToPage(page1: number) {
    const p = Math.max(1, Math.min(totalPages, page1))
    setOffset((p - 1) * PAGE_SIZE)
  }

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
                Users
              </h1>
              <p className="mt-1 text-sm text-gray-400">Search, filter, and moderate accounts.</p>
            </div>
            <Link href="/admin" className="rounded bg-white/10 px-3 py-2 text-sm hover:bg-white/20">
              Back to Admin
            </Link>
          </div>

          <section className="rounded-xl border border-white/10 bg-white/5 p-4 md:p-5">
            <div className="flex flex-col gap-3 md:flex-row md:flex-wrap md:items-end">
              <div className="min-w-[200px] flex-1">
                <label className="text-xs text-gray-400">Search</label>
                <input
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  placeholder="Username, name, or email"
                  className="mt-1 w-full rounded-lg border border-white/10 bg-[#111827] px-3 py-2 text-sm text-white placeholder-gray-500"
                />
              </div>
              <div>
                <label className="text-xs text-gray-400">Ban status</label>
                <CustomSelect
                  value={bannedFilter}
                  onChange={(val) => setBannedFilter(val as typeof bannedFilter)}
                  className="mt-1 md:w-40"
                  triggerClassName={SELECT_TRIGGER_CLASS}
                  options={[
                    { label: "All", value: "all" },
                    { label: "Banned", value: "banned" },
                    { label: "Active", value: "active" },
                  ]}
                />
              </div>
              <div>
                <label className="text-xs text-gray-400">Pro</label>
                <CustomSelect
                  value={proFilter}
                  onChange={(val) => setProFilter(val as typeof proFilter)}
                  className="mt-1 md:w-40"
                  triggerClassName={SELECT_TRIGGER_CLASS}
                  options={[
                    { label: "All", value: "all" },
                    { label: "Pro", value: "pro" },
                    { label: "Non‑Pro", value: "non_pro" },
                  ]}
                />
              </div>
              <div>
                <label className="text-xs text-gray-400">Privacy</label>
                <CustomSelect
                  value={privacyFilter}
                  onChange={(val) => setPrivacyFilter(val as typeof privacyFilter)}
                  className="mt-1 md:w-40"
                  triggerClassName={SELECT_TRIGGER_CLASS}
                  options={[
                    { label: "All", value: "all" },
                    { label: "Private", value: "private" },
                    { label: "Public", value: "public" },
                  ]}
                />
              </div>
            </div>

            {listError ? (
              <p className="mt-3 text-sm text-red-300">
                {listError}. Ensure migrations for <code className="rounded bg-black/30 px-1">admin_list_users</code>{" "}
                are applied.
              </p>
            ) : null}

            <div className="mt-4 flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-center sm:justify-between">
              <div className="text-sm text-gray-400">
                <span className="tabular-nums">
                  Showing {rangeStart}–{rangeEnd} of {total}
                </span>
                <span className="mx-2 text-gray-600">·</span>
                <span className="tabular-nums">
                  Page {currentPage} of {totalPages}
                </span>
                {listLoading ? <span className="ml-2 text-gray-500">Loading…</span> : null}
              </div>
              <div className="flex flex-wrap items-center gap-2">
                <button
                  type="button"
                  disabled={!canPrev || listLoading}
                  onClick={() => setOffset((o) => Math.max(0, o - PAGE_SIZE))}
                  className="rounded bg-white/10 px-3 py-1.5 text-sm hover:bg-white/20 disabled:cursor-not-allowed disabled:opacity-40"
                >
                  Previous
                </button>
                <button
                  type="button"
                  disabled={!canNext || listLoading}
                  onClick={() => setOffset((o) => o + PAGE_SIZE)}
                  className="rounded bg-white/10 px-3 py-1.5 text-sm hover:bg-white/20 disabled:cursor-not-allowed disabled:opacity-40"
                >
                  Next
                </button>
                {totalPages > 1 && totalPages <= 12 ? (
                  <div className="flex flex-wrap gap-1 border-l border-white/10 pl-2">
                    {Array.from({ length: totalPages }, (_, i) => i + 1).map((p) => (
                      <button
                        key={p}
                        type="button"
                        disabled={listLoading || p === currentPage}
                        onClick={() => goToPage(p)}
                        className={`min-w-[2rem] rounded px-2 py-1 text-xs tabular-nums ${
                          p === currentPage ? "bg-blue-500 text-white" : "bg-white/10 text-gray-200 hover:bg-white/20"
                        } disabled:opacity-50`}
                      >
                        {p}
                      </button>
                    ))}
                  </div>
                ) : null}
              </div>
            </div>

            {/* TEMPORARY BETA CLEANUP TOOL — bulk multi-select delete; remove after launch. */}
            <div className="mt-4 flex flex-col gap-3 rounded-lg border border-amber-500/30 bg-amber-950/20 p-3 sm:flex-row sm:flex-wrap sm:items-center sm:justify-between">
              <div className="text-sm text-amber-100/90">
                <span className="font-medium text-amber-200">Beta cleanup:</span>{" "}
                Selected: <span className="tabular-nums font-semibold text-white">{bulkSelectedCount}</span>{" "}
                {bulkSelectedCount === 1 ? "user" : "users"}
              </div>
              <div className="flex flex-wrap gap-2">
                <button
                  type="button"
                  disabled={bulkSelectedCount === 0 || bulkDeleteBusy}
                  onClick={() => setBulkSelectedIds(new Set())}
                  className="rounded bg-white/10 px-3 py-1.5 text-sm hover:bg-white/20 disabled:cursor-not-allowed disabled:opacity-40"
                >
                  Clear selection
                </button>
                <button
                  type="button"
                  disabled={bulkSelectedCount === 0 || bulkDeleteBusy}
                  onClick={openBulkDeleteModal}
                  className="rounded border border-red-400/40 bg-red-600/30 px-3 py-1.5 text-sm font-semibold text-red-100 hover:bg-red-600/40 disabled:cursor-not-allowed disabled:opacity-40"
                >
                  Delete selected
                </button>
              </div>
            </div>

            <div className="mt-4 overflow-x-auto rounded-lg border border-white/10">
              <table className="min-w-full divide-y divide-white/10 text-left text-sm">
                <thead className="bg-black/30 text-xs uppercase text-gray-400">
                  <tr>
                    <th className="w-10 px-2 py-2">
                      <input
                        type="checkbox"
                        aria-label="Select all users on this page"
                        checked={allDeletableOnPageSelected}
                        ref={(el) => {
                          if (el) el.indeterminate = someDeletableOnPageSelected
                        }}
                        disabled={deletableRowsOnPage.length === 0 || bulkDeleteBusy}
                        onChange={toggleBulkSelectAllOnPage}
                        className="h-4 w-4 rounded border-white/20 bg-[#111827] accent-red-500"
                      />
                    </th>
                    <th className="px-3 py-2">User</th>
                    <th className="px-3 py-2">Email</th>
                    <th className="px-3 py-2">Joined</th>
                    <th className="px-3 py-2">Pro</th>
                    <th className="px-3 py-2">Private</th>
                    <th className="px-3 py-2">Banned</th>
                    <th className="px-3 py-2">Beta</th>
                    <th className="px-3 py-2">Referral</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-white/5">
                  {!listLoading && rows.length === 0 ? (
                    <tr>
                      <td colSpan={9} className="px-3 py-6 text-center text-gray-400">
                        No users match these filters.
                      </td>
                    </tr>
                  ) : null}
                  {rows.map((row) => {
                    const pro = isProActive({ is_pro: row.is_pro, subscription_status: row.subscription_status })
                    const rowDeletable = isBulkDeletable(row)
                    const rowSelected = bulkSelectedIds.has(row.id)
                    return (
                      <tr
                        key={row.id}
                        className={`cursor-pointer hover:bg-white/5 ${rowSelected ? "bg-red-950/20" : ""}`}
                        onClick={() => openRow(row)}
                      >
                        <td className="px-2 py-2" onClick={(e) => e.stopPropagation()}>
                          <input
                            type="checkbox"
                            aria-label={`Select ${bulkUserLabel(row)}`}
                            checked={rowSelected}
                            disabled={!rowDeletable || bulkDeleteBusy}
                            title={
                              !rowDeletable
                                ? row.id === adminUserId
                                  ? "Cannot delete your own account"
                                  : adminUserIds.has(row.id)
                                    ? "Cannot delete admin accounts"
                                    : "Cannot select"
                                : undefined
                            }
                            onChange={() => toggleBulkSelectRow(row)}
                            className="h-4 w-4 rounded border-white/20 bg-[#111827] accent-red-500 disabled:opacity-40"
                          />
                        </td>
                        <td className="px-3 py-2">
                          <div className="flex items-center gap-2">
                            <ProfileAvatarImg
                              src={row.avatar_url}
                              className="h-8 w-8"
                            />
                            <div className="min-w-0">
                              <p className="truncate font-medium text-white">@{row.username || "—"}</p>
                              <p className="truncate text-xs text-gray-400">{row.name || "—"}</p>
                            </div>
                          </div>
                        </td>
                        <td className="max-w-[180px] truncate px-3 py-2 text-gray-300">{row.email || "—"}</td>
                        <td className="whitespace-nowrap px-3 py-2 text-xs text-gray-400 tabular-nums">
                          {row.created_at ? new Date(row.created_at).toLocaleDateString() : "—"}
                        </td>
                        <td className="px-3 py-2">{pro ? <span className="text-emerald-400">Yes</span> : <span className="text-gray-500">No</span>}</td>
                        <td className="px-3 py-2">{row.is_private ? "Yes" : "No"}</td>
                        <td className="px-3 py-2">{row.is_banned ? <span className="text-red-300">Yes</span> : "No"}</td>
                        <td className="px-3 py-2">
                          {row.is_beta_tester ? (
                            <span className="text-amber-400">Yes</span>
                          ) : (
                            <span className="text-gray-500">No</span>
                          )}
                        </td>
                        <td className="max-w-[100px] truncate px-3 py-2 text-xs text-gray-400">{row.referral_code || "—"}</td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </div>

      {selected ? (
        <div
          className="fixed inset-0 z-[130] flex items-center justify-center bg-black/70 p-3 backdrop-blur-sm md:p-6"
          onClick={() => setSelected(null)}
        >
          <div
            className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-xl border border-white/10 bg-[#0f172a] p-5 text-white shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-center gap-3">
                <ProfileAvatarImg
                  src={selected.avatar_url}
                  className="h-12 w-12"
                />
                <div>
                  <h2 className="text-lg font-semibold">@{selected.username}</h2>
                  <p className="text-sm text-gray-400">{selected.name || "—"}</p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setSelected(null)}
                className="rounded bg-white/10 px-3 py-1 text-sm hover:bg-white/20"
              >
                Close
              </button>
            </div>

            <dl className="mt-4 space-y-2 text-sm">
              <div className="flex justify-between gap-2">
                <dt className="text-gray-500">User id</dt>
                <dd className="truncate font-mono text-xs text-gray-300">{selected.id}</dd>
              </div>
              <div className="flex justify-between gap-2">
                <dt className="text-gray-500">Email</dt>
                <dd className="truncate text-gray-200">{selected.email || "—"}</dd>
              </div>
              <div className="flex justify-between gap-2">
                <dt className="text-gray-500">Joined</dt>
                <dd className="text-gray-200 tabular-nums">
                  {selected.created_at ? new Date(selected.created_at).toLocaleString() : "—"}
                </dd>
              </div>
              <div className="flex justify-between gap-2">
                <dt className="text-gray-500">Pro</dt>
                <dd className="text-gray-200">
                  {isProActive({ is_pro: selected.is_pro, subscription_status: selected.subscription_status }) ? (
                    <span className="text-emerald-400">Yes</span>
                  ) : (
                    <span className="text-gray-400">No</span>
                  )}
                </dd>
              </div>
              <div className="flex justify-between gap-2">
                <dt className="text-gray-500">Privacy</dt>
                <dd className="text-gray-200">{selected.is_private ? "Private" : "Public"}</dd>
              </div>
              <div className="flex justify-between gap-2">
                <dt className="text-gray-500">Banned</dt>
                <dd className={selected.is_banned ? "text-red-300" : "text-gray-200"}>
                  {selected.is_banned ? "Yes" : "No"}
                </dd>
              </div>
              <div className="flex justify-between gap-2">
                <dt className="text-gray-500">Beta tester</dt>
                <dd className={selected.is_beta_tester ? "text-amber-400" : "text-gray-200"}>
                  {selected.is_beta_tester ? "Yes" : "No"}
                </dd>
              </div>
              <div className="flex justify-between gap-2">
                <dt className="text-gray-500">Subscription</dt>
                <dd className="text-gray-200">{selected.subscription_status || "—"}</dd>
              </div>
              <div className="flex justify-between gap-2">
                <dt className="text-gray-500">Referral code</dt>
                <dd className="truncate text-gray-200">{selected.referral_code || "—"}</dd>
              </div>
            </dl>

            <div className="mt-4">
              <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-500">Activity (database)</h3>
              {countsError ? (
                <p className="mt-2 text-xs text-gray-400">
                  Counts unavailable: {countsError}
                </p>
              ) : null}
              <div className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-3">
                <div className="rounded-lg border border-white/10 bg-black/30 p-3 text-center">
                  <p className="text-xs text-gray-500">Trades</p>
                  <p className="text-xl font-semibold tabular-nums text-white">
                    {countsLoading ? "…" : counts?.trades ?? "—"}
                  </p>
                </div>
                <div className="rounded-lg border border-white/10 bg-black/30 p-3 text-center">
                  <p className="text-xs text-gray-500">Posts</p>
                  <p className="text-xl font-semibold tabular-nums text-white">
                    {countsLoading ? "…" : counts?.posts ?? "—"}
                  </p>
                </div>
                <div className="rounded-lg border border-white/10 bg-black/30 p-3 text-center">
                  <p className="text-xs text-gray-500">Achievements</p>
                  <p className="text-xl font-semibold tabular-nums text-white">
                    {countsLoading ? "…" : counts?.achievements ?? "—"}
                  </p>
                </div>
                <div className="rounded-lg border border-white/10 bg-black/30 p-3 text-center">
                  <p className="text-xs text-gray-500">Feedback</p>
                  <p className="text-xl font-semibold tabular-nums text-white">
                    {countsLoading ? "…" : counts?.feedback ?? "—"}
                  </p>
                </div>
                <div className="rounded-lg border border-white/10 bg-black/30 p-3 text-center">
                  <p className="text-xs text-gray-500">Support tickets</p>
                  <p className="text-xl font-semibold tabular-nums text-white">
                    {countsLoading ? "…" : counts?.supportTickets ?? "—"}
                  </p>
                </div>
              </div>
            </div>

            <div className="mt-6 rounded-lg border border-white/10 bg-black/30 p-4">
              <h3 className="text-sm font-semibold text-gray-200">Moderation</h3>
              {selected.is_banned ? (
                <p className="mt-2 text-xs text-red-300">This user is banned.</p>
              ) : (
                <label className="mt-2 block text-xs text-gray-400">
                  Ban reason (required to ban)
                  <textarea
                    value={banReason}
                    onChange={(e) => setBanReason(e.target.value)}
                    rows={3}
                    className="mt-1 w-full rounded border border-white/10 bg-[#111827] p-2 text-sm text-white"
                    placeholder="Explain why this account is being suspended…"
                  />
                </label>
              )}
              <div className="mt-3 flex flex-wrap gap-2">
                {selected.is_banned ? (
                  <button
                    type="button"
                    disabled={moderationBusy || deleteView}
                    onClick={() => void handleUnban()}
                    className="rounded bg-blue-500 px-4 py-2 text-sm font-semibold hover:bg-blue-600 disabled:opacity-50 disabled:hover:bg-blue-500"
                  >
                    Unban user
                  </button>
                ) : (
                  <button
                    type="button"
                    disabled={moderationBusy || deleteView}
                    onClick={() => void handleBan()}
                    className="rounded bg-red-600 px-4 py-2 text-sm font-semibold hover:bg-red-500 disabled:opacity-50"
                  >
                    Ban user
                  </button>
                )}
              </div>
            </div>

            <div className="mt-6 rounded-lg border border-red-500/30 bg-red-950/20 p-4">
              <h3 className="text-sm font-semibold text-red-200">Danger zone</h3>
              <p className="mt-1 text-xs text-red-200/80">
                Permanently remove this account and all associated data. For internal administration and test-account cleanup only.
              </p>

              {!deleteView ? (
                <button
                  type="button"
                  disabled={Boolean(deleteBlockedReason)}
                  onClick={() => void openDeleteView()}
                  className="mt-3 rounded border border-red-400/40 bg-red-600/20 px-4 py-2 text-sm font-semibold text-red-100 hover:bg-red-600/30 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  Delete user
                </button>
              ) : null}

              {deleteBlockedReason ? (
                <p className="mt-2 text-xs text-amber-300">{deleteBlockedReason}</p>
              ) : null}

              {deleteView ? (
                <div className="mt-4 space-y-4 border-t border-red-500/20 pt-4">
                  <div className="flex items-center justify-between gap-2">
                    <h4 className="text-sm font-medium text-red-100">Review before deletion</h4>
                    <button
                      type="button"
                      onClick={() => {
                        setDeleteView(false)
                        setDeleteConfirm("")
                        setDeleteError(null)
                      }}
                      className="rounded bg-white/10 px-2 py-1 text-xs hover:bg-white/20"
                    >
                      Back
                    </button>
                  </div>

                  {deletePreviewLoading ? (
                    <p className="text-sm text-gray-400">Loading account summary…</p>
                  ) : deletePreview ? (
                    <dl className="grid grid-cols-1 gap-2 text-sm sm:grid-cols-2">
                      {[
                        ["Username", deletePreview.username ? `@${String(deletePreview.username)}` : "—"],
                        ["Email", deletePreview.email || "—"],
                        [
                          "Created",
                          deletePreview.createdAt
                            ? new Date(String(deletePreview.createdAt)).toLocaleString()
                            : "—",
                        ],
                        [
                          "Last login",
                          deletePreview.lastLoginAt
                            ? new Date(String(deletePreview.lastLoginAt)).toLocaleString()
                            : "—",
                        ],
                        ["Subscription", deletePreview.subscriptionStatus || "—"],
                        ["Beta tester", deletePreview.isBetaTester ? "Yes" : "No"],
                        ["Trades", deletePreview.tradeCount],
                        ["Posts", deletePreview.postCount],
                        ["Comments", deletePreview.commentCount],
                        ["Messages", deletePreview.messageCount],
                        ["Rooms owned", deletePreview.roomOwnershipCount],
                        ["Followers", deletePreview.followerCount],
                        ["Affiliate", deletePreview.affiliateStatus || "—"],
                        ["Stripe customer", deletePreview.stripeCustomerId || "—"],
                      ].map(([label, value]) => (
                        <div key={label} className="flex justify-between gap-2 rounded bg-black/30 px-3 py-2">
                          <dt className="text-gray-500">{label}</dt>
                          <dd className="truncate text-right text-gray-200">{String(value)}</dd>
                        </div>
                      ))}
                    </dl>
                  ) : null}

                  <div className="rounded-lg border border-red-500/30 bg-black/40 p-3 text-xs leading-relaxed text-red-100/90">
                    <p className="font-semibold text-red-200">This action permanently removes:</p>
                    <ul className="mt-2 list-inside list-disc space-y-1">
                      <li>Profile</li>
                      <li>Trades</li>
                      <li>Posts</li>
                      <li>Comments</li>
                      <li>Messages</li>
                      <li>Notifications</li>
                      <li>Followers</li>
                      <li>Trade Rooms</li>
                      <li>Affiliate data</li>
                    </ul>
                    <p className="mt-2 font-medium">This cannot be undone.</p>
                  </div>

                  <label className="block text-xs text-gray-400">
                    Type <span className="font-mono text-red-200">DELETE</span> to enable deletion
                    <input
                      value={deleteConfirm}
                      onChange={(e) => setDeleteConfirm(e.target.value)}
                      autoComplete="off"
                      spellCheck={false}
                      className="mt-1 w-full rounded border border-white/10 bg-[#111827] p-2 font-mono text-sm text-white"
                      placeholder="DELETE"
                    />
                  </label>

                  {deleteError ? (
                    <div className="rounded-lg border border-red-500/30 bg-red-950/30 p-3 text-sm text-red-200">
                      {deleteError.message}
                    </div>
                  ) : null}

                  <button
                    type="button"
                    disabled={deleteBusy || deleteConfirm !== "DELETE" || deletePreviewLoading}
                    onClick={() => void handleDeleteUser()}
                    className="w-full rounded bg-red-600 px-4 py-2 text-sm font-semibold text-white hover:bg-red-500 disabled:cursor-not-allowed disabled:opacity-50"
                  >
                    {deleteBusy ? "Deleting…" : "Permanently delete user"}
                  </button>
                </div>
              ) : null}
            </div>
          </div>
        </div>
      ) : null}

      {/* TEMPORARY BETA CLEANUP TOOL — bulk delete confirmation + results */}
      {bulkDeleteModalOpen ? (
        <div
          className="fixed inset-0 z-[140] flex items-center justify-center bg-black/70 p-3 backdrop-blur-sm md:p-6"
          onClick={() => closeBulkDeleteModal()}
        >
          <div
            className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-xl border border-red-500/30 bg-[#0f172a] p-5 text-white shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-start justify-between gap-3">
              <div>
                <h2 className="text-lg font-semibold text-red-100">Delete selected users</h2>
                <p className="mt-1 text-sm text-gray-400">
                  Pre-beta cleanup. Uses the same permanent delete workflow as single-user deletion.
                </p>
              </div>
              <button
                type="button"
                disabled={bulkDeleteBusy}
                onClick={() => closeBulkDeleteModal()}
                className="rounded bg-white/10 px-3 py-1 text-sm hover:bg-white/20 disabled:opacity-50"
              >
                Close
              </button>
            </div>

            {bulkDeleteOutcome ? (
              <div className="mt-4 space-y-4">
                <div className="grid grid-cols-3 gap-2 text-center text-sm">
                  <div className="rounded-lg border border-emerald-500/30 bg-emerald-950/30 p-3">
                    <p className="text-xs text-emerald-300">Deleted</p>
                    <p className="text-2xl font-semibold tabular-nums text-white">
                      {bulkDeleteOutcome.deleted.length}
                    </p>
                  </div>
                  <div className="rounded-lg border border-amber-500/30 bg-amber-950/30 p-3">
                    <p className="text-xs text-amber-300">Skipped</p>
                    <p className="text-2xl font-semibold tabular-nums text-white">
                      {bulkDeleteOutcome.skipped.length}
                    </p>
                  </div>
                  <div className="rounded-lg border border-red-500/30 bg-red-950/30 p-3">
                    <p className="text-xs text-red-300">Failed</p>
                    <p className="text-2xl font-semibold tabular-nums text-white">
                      {bulkDeleteOutcome.failed.length}
                    </p>
                  </div>
                </div>

                {bulkDeleteOutcome.skipped.length > 0 ? (
                  <div>
                    <h3 className="text-xs font-semibold uppercase tracking-wide text-amber-300">Skipped</h3>
                    <ul className="mt-2 max-h-32 space-y-1 overflow-y-auto text-sm text-gray-300">
                      {bulkDeleteOutcome.skipped.map((u) => (
                        <li key={u.id}>
                          <span className="font-medium text-white">{u.username}</span>
                          <span className="text-gray-500">, {u.reason}</span>
                        </li>
                      ))}
                    </ul>
                  </div>
                ) : null}

                {bulkDeleteOutcome.failed.length > 0 ? (
                  <div>
                    <h3 className="text-xs font-semibold uppercase tracking-wide text-red-300">Failed</h3>
                    <ul className="mt-2 max-h-40 space-y-2 overflow-y-auto text-sm">
                      {bulkDeleteOutcome.failed.map((u) => (
                        <li key={u.id} className="rounded border border-red-500/20 bg-red-950/20 p-2">
                          <p className="font-medium text-red-100">{u.username}</p>
                          <p className="text-xs text-red-200/90">{u.message}</p>
                        </li>
                      ))}
                    </ul>
                  </div>
                ) : null}

                {bulkDeleteOutcome.deleted.length > 0 ? (
                  <div>
                    <h3 className="text-xs font-semibold uppercase tracking-wide text-emerald-300">Deleted</h3>
                    <p className="mt-1 text-sm text-gray-400">
                      {bulkDeleteOutcome.deleted.map((u) => u.username).join(", ")}
                    </p>
                  </div>
                ) : null}

                <button
                  type="button"
                  onClick={() => closeBulkDeleteModal()}
                  className="w-full rounded bg-white/10 px-4 py-2 text-sm font-semibold hover:bg-white/20"
                >
                  Done
                </button>
              </div>
            ) : (
              <div className="mt-4 space-y-4">
                <p className="text-sm text-gray-300">
                  You are about to permanently delete{" "}
                  <span className="font-semibold text-white tabular-nums">{bulkSelectedCount}</span>{" "}
                  {bulkSelectedCount === 1 ? "user" : "users"}.
                </p>
                <ul className="max-h-48 space-y-1 overflow-y-auto rounded-lg border border-white/10 bg-black/30 p-3 text-sm">
                  {bulkModalRows.map((row) => (
                    <li key={row.id} className="text-gray-200">
                      {bulkUserLabel(row)}
                      {!isBulkDeletable(row) ? (
                        <span className="ml-2 text-xs text-amber-400">(will be skipped)</span>
                      ) : null}
                    </li>
                  ))}
                </ul>
                <label className="block text-xs text-gray-400">
                  Type <span className="font-mono text-red-200">DELETE</span> to confirm
                  <input
                    value={bulkDeleteConfirm}
                    onChange={(e) => setBulkDeleteConfirm(e.target.value)}
                    autoComplete="off"
                    spellCheck={false}
                    disabled={bulkDeleteBusy}
                    className="mt-1 w-full rounded border border-white/10 bg-[#111827] p-2 font-mono text-sm text-white"
                    placeholder="DELETE"
                  />
                </label>
                <button
                  type="button"
                  disabled={bulkDeleteBusy || bulkDeleteConfirm !== "DELETE"}
                  onClick={() => void handleBulkDeleteSelected()}
                  className="w-full rounded bg-red-600 px-4 py-2 text-sm font-semibold text-white hover:bg-red-500 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  {bulkDeleteBusy ? "Deleting…" : "Permanently delete selected"}
                </button>
              </div>
            )}
          </div>
        </div>
      ) : null}
    </>
  )
}
