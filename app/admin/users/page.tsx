"use client"

import Link from "next/link"
import { useCallback, useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Navbar from "@/app/components/Navbar"
import { getCurrentAdminCheckResult } from "@/lib/adminUsers"
import { banUser, unbanUser } from "@/lib/adminModeration"
import {
  type AdminUserActivityCounts,
  type AdminUserListRow,
  fetchAdminUserDirectory,
  fetchUserActivityCounts,
} from "@/lib/adminUsersDirectory"
import { isProActive } from "@/lib/subscription"
import { supabase } from "@/lib/supabaseClient"

const PAGE_SIZE = 20

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
      setListError(error.message)
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
        setCountsError(error.message)
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
  }

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
      alert(error.message)
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
      alert(error.message)
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
        <Navbar />
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-8 text-white">
          Checking admin access…
        </div>
      </>
    )
  }

  return (
    <>
      <Navbar />
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-4 text-gray-100 md:p-8">
        <div className="mx-auto max-w-6xl space-y-6">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <h1 className="text-2xl font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent md:text-3xl">
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
                <select
                  value={bannedFilter}
                  onChange={(e) => setBannedFilter(e.target.value as typeof bannedFilter)}
                  className="mt-1 w-full rounded-lg border border-white/10 bg-[#111827] px-3 py-2 text-sm md:w-40"
                >
                  <option value="all">All</option>
                  <option value="banned">Banned</option>
                  <option value="active">Active</option>
                </select>
              </div>
              <div>
                <label className="text-xs text-gray-400">Pro</label>
                <select
                  value={proFilter}
                  onChange={(e) => setProFilter(e.target.value as typeof proFilter)}
                  className="mt-1 w-full rounded-lg border border-white/10 bg-[#111827] px-3 py-2 text-sm md:w-40"
                >
                  <option value="all">All</option>
                  <option value="pro">Pro</option>
                  <option value="non_pro">Non‑Pro</option>
                </select>
              </div>
              <div>
                <label className="text-xs text-gray-400">Privacy</label>
                <select
                  value={privacyFilter}
                  onChange={(e) => setPrivacyFilter(e.target.value as typeof privacyFilter)}
                  className="mt-1 w-full rounded-lg border border-white/10 bg-[#111827] px-3 py-2 text-sm md:w-40"
                >
                  <option value="all">All</option>
                  <option value="private">Private</option>
                  <option value="public">Public</option>
                </select>
              </div>
            </div>

            {listError ? (
              <p className="mt-3 text-sm text-red-300">
                {listError} — ensure migrations for <code className="rounded bg-black/30 px-1">admin_list_users</code>{" "}
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
                          p === currentPage ? "bg-emerald-600 text-white" : "bg-white/10 text-gray-200 hover:bg-white/20"
                        } disabled:opacity-50`}
                      >
                        {p}
                      </button>
                    ))}
                  </div>
                ) : null}
              </div>
            </div>

            <div className="mt-4 overflow-x-auto rounded-lg border border-white/10">
              <table className="min-w-full divide-y divide-white/10 text-left text-sm">
                <thead className="bg-black/30 text-xs uppercase text-gray-400">
                  <tr>
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
                      <td colSpan={8} className="px-3 py-6 text-center text-gray-400">
                        No users match these filters.
                      </td>
                    </tr>
                  ) : null}
                  {rows.map((row) => {
                    const pro = isProActive({ is_pro: row.is_pro, subscription_status: row.subscription_status })
                    return (
                      <tr
                        key={row.id}
                        className="cursor-pointer hover:bg-white/5"
                        onClick={() => openRow(row)}
                      >
                        <td className="px-3 py-2">
                          <div className="flex items-center gap-2">
                            <div className="relative h-8 w-8 shrink-0 overflow-hidden rounded-full bg-gray-700">
                              {row.avatar_url ? (
                                <img src={row.avatar_url} alt="" className="h-full w-full object-cover" />
                              ) : null}
                            </div>
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
                <div className="relative h-12 w-12 shrink-0 overflow-hidden rounded-full bg-gray-700">
                  {selected.avatar_url ? (
                    <img src={selected.avatar_url} alt="" className="h-full w-full object-cover" />
                  ) : null}
                </div>
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
                    disabled={moderationBusy}
                    onClick={() => void handleUnban()}
                    className="rounded bg-emerald-600 px-4 py-2 text-sm font-semibold hover:bg-emerald-500 disabled:opacity-50"
                  >
                    Unban user
                  </button>
                ) : (
                  <button
                    type="button"
                    disabled={moderationBusy}
                    onClick={() => void handleBan()}
                    className="rounded bg-red-600 px-4 py-2 text-sm font-semibold hover:bg-red-500 disabled:opacity-50"
                  >
                    Ban user
                  </button>
                )}
              </div>
            </div>
          </div>
        </div>
      ) : null}
    </>
  )
}
