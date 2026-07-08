"use client"

import Link from "next/link"
import { useCallback, useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import {
  fetchAdminPayoutRequests,
  fetchAdminPayoutStatusCounts,
  type AdminPayoutRequestRow,
  type AdminPayoutStatusCounts,
  type AffiliatePayoutStatusFilter,
} from "@/lib/adminAffiliatePayoutRequests"
import { getCurrentAdminCheckResult } from "@/lib/adminUsers"
import { logPostgrestErrorDev } from "@/lib/postgrestError"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"
import { supabase } from "@/lib/supabaseClient"

type TabId = AffiliatePayoutStatusFilter

const TABS: { id: TabId; label: string }[] = [
  ["pending", "Pending"],
  ["approved", "Approved"],
  ["paid", "Paid"],
  ["rejected", "Rejected"],
  ["all", "All"],
].map(([id, label]) => ({ id: id as TabId, label }))

function formatTs(iso: string | null | undefined): string {
  if (!iso) return "—"
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return "—"
  return d.toLocaleString()
}

function formatMoney(n: number): string {
  return n.toFixed(2)
}

function userLabel(row: AdminPayoutRequestRow): string {
  const bits = [row.username?.trim() || null, row.name?.trim() || null].filter(Boolean)
  if (bits.length) return bits.join(" · ")
  return row.user_id.slice(0, 8) + "…"
}

function statusBadgeClass(status: string): string {
  switch (status) {
    case "pending":
      return "border-amber-500/40 bg-amber-500/15 text-amber-100"
    case "approved":
      return "border-blue-500/40 bg-blue-500/15 text-blue-100"
    case "paid":
      return "border-emerald-500/40 bg-emerald-500/15 text-emerald-100"
    case "rejected":
      return "border-red-500/40 bg-red-500/15 text-red-100"
    default:
      return "border-white/15 bg-white/10 text-gray-200"
  }
}

export default function AdminPayoutRequestsPage() {
  const router = useRouter()
  const [checking, setChecking] = useState(true)
  const [allowed, setAllowed] = useState(false)
  const [adminUserId, setAdminUserId] = useState<string | null>(null)
  const [tab, setTab] = useState<TabId>("pending")
  const [rows, setRows] = useState<AdminPayoutRequestRow[]>([])
  const [counts, setCounts] = useState<AdminPayoutStatusCounts | null>(null)
  const [loading, setLoading] = useState(false)
  const [selected, setSelected] = useState<AdminPayoutRequestRow | null>(null)
  const [notesDraft, setNotesDraft] = useState("")
  const [actionBusy, setActionBusy] = useState(false)
  const [actionError, setActionError] = useState<string | null>(null)
  const [listError, setListError] = useState<string | null>(null)

  const loadRows = useCallback(async (): Promise<AdminPayoutRequestRow[]> => {
    if (!allowed) return []
    setLoading(true)
    setListError(null)

    const [listRes, countRes] = await Promise.all([
      fetchAdminPayoutRequests(supabase, tab),
      fetchAdminPayoutStatusCounts(supabase),
    ])

    if (listRes.error) {
      logPostgrestErrorDev("admin payout requests list", listRes.error as unknown as Error)
      setListError(listRes.error.message)
      setRows([])
      setLoading(false)
      return []
    }

    setRows(listRes.rows)
    if (!countRes.error && countRes.counts) setCounts(countRes.counts)
    else if (countRes.error) setCounts(null)

    setLoading(false)
    return listRes.rows
  }, [allowed, tab])

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
    void loadRows()
  }, [loadRows])

  useEffect(() => {
    setSelected(null)
    setActionError(null)
  }, [tab])

  function openDetail(row: AdminPayoutRequestRow) {
    setSelected(row)
    setNotesDraft(row.admin_notes?.trim() ?? "")
    setActionError(null)
  }

  function closeDetail() {
    setSelected(null)
    setActionError(null)
  }

  function applyReselectOrClose(requestId: string, nextRows: AdminPayoutRequestRow[]) {
    const next = nextRows.find((r) => r.id === requestId)
    if (next) {
      setSelected(next)
      setNotesDraft(next.admin_notes?.trim() ?? "")
    } else {
      closeDetail()
    }
  }

  async function toolbarRefresh() {
    const requestId = selected?.id
    const nextRows = await loadRows()
    if (requestId) applyReselectOrClose(requestId, nextRows)
  }

  async function handleApprove() {
    if (!selected?.id || !adminUserId) return
    const requestId = selected.id
    setActionBusy(true)
    setActionError(null)
    const { error } = await supabase
      .from("affiliate_payout_requests")
      .update({
        status: "approved",
        reviewed_at: new Date().toISOString(),
        reviewed_by: adminUserId,
        admin_notes: notesDraft.trim() || null,
      })
      .eq("id", requestId)

    setActionBusy(false)
    if (error) {
      logPostgrestErrorDev("admin payout approve", error)
      setActionError(error.message)
      return
    }
    const nextRows = await loadRows()
    applyReselectOrClose(requestId, nextRows)
  }

  async function handleReject() {
    if (!selected?.id || !adminUserId) return
    const requestId = selected.id
    setActionBusy(true)
    setActionError(null)
    const { error } = await supabase
      .from("affiliate_payout_requests")
      .update({
        status: "rejected",
        reviewed_at: new Date().toISOString(),
        reviewed_by: adminUserId,
        admin_notes: notesDraft.trim() || null,
      })
      .eq("id", requestId)

    setActionBusy(false)
    if (error) {
      logPostgrestErrorDev("admin payout reject", error)
      setActionError(error.message)
      return
    }
    const nextRows = await loadRows()
    applyReselectOrClose(requestId, nextRows)
  }

  async function handleMarkPaid() {
    if (!selected?.id || !adminUserId) return
    const requestId = selected.id
    setActionBusy(true)
    setActionError(null)
    try {
      const authHeaders = await supabaseBearerHeaders()
      const res = await fetch("/api/admin/affiliate-payout-requests/execute", {
        method: "POST",
        credentials: "include",
        headers: {
          "Content-Type": "application/json",
          ...authHeaders,
        },
        body: JSON.stringify({
          payoutRequestId: requestId,
          adminNotes: notesDraft.trim() || null,
        }),
      })
      const data = (await res.json().catch(() => ({}))) as { ok?: boolean; error?: string }
      if (!res.ok) {
        setActionError(typeof data.error === "string" ? data.error : "Could not complete Stripe transfer.")
        return
      }
      const nextRows = await loadRows()
      applyReselectOrClose(requestId, nextRows)
    } catch (e) {
      setActionError(e instanceof Error ? e.message : "Could not complete Stripe transfer.")
    } finally {
      setActionBusy(false)
    }
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
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100 p-4 md:p-8">
        <div className="mx-auto max-w-5xl space-y-6">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div>
              <Link href="/admin" className="text-sm text-blue-300 hover:text-blue-200">
                ← Admin home
              </Link>
              <h1 className="mt-2 text-2xl font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent md:text-3xl">
                Affiliate payout requests
              </h1>
              <p className="mt-1 text-sm text-gray-400">
                Marking approved requests paid creates a Stripe{" "}
                <strong className="text-gray-300">Transfer</strong> from your platform balance to the
                affiliate&apos;s <strong className="text-gray-300">connected account</strong>. Stripe then pays
                out to their bank on its own schedule (e.g. daily). Confirm transfers in Dashboard →{" "}
                <span className="font-mono text-gray-300">Transfers</span>; bank payouts appear on the connected
                account&apos;s payout timeline.
              </p>
            </div>
            <button
              type="button"
              onClick={() => void toolbarRefresh()}
              disabled={loading}
              className="rounded-lg bg-white/10 px-4 py-2 text-sm hover:bg-white/20 disabled:opacity-50"
            >
              {loading ? "Refreshing…" : "Refresh"}
            </button>
          </div>

          {counts ? (
            <div className="flex flex-wrap gap-3 rounded-xl border border-white/10 bg-white/5 px-4 py-3 text-sm">
              <span className="text-gray-400">
                Pending: <span className="font-semibold tabular-nums text-amber-200">{counts.pending}</span>
              </span>
              <span className="text-gray-600">·</span>
              <span className="text-gray-400">
                Approved: <span className="font-semibold tabular-nums text-blue-200">{counts.approved}</span>
              </span>
              <span className="text-gray-600">·</span>
              <span className="text-gray-400">
                Paid: <span className="font-semibold tabular-nums text-emerald-200">{counts.paid}</span>
              </span>
              <span className="text-gray-600">·</span>
              <span className="text-gray-400">
                Rejected: <span className="font-semibold tabular-nums text-red-200/90">{counts.rejected}</span>
              </span>
              <span className="text-gray-600">·</span>
              <span className="text-gray-400">
                Total: <span className="font-semibold tabular-nums text-white">{counts.all}</span>
              </span>
            </div>
          ) : null}

          <div className="flex flex-wrap gap-2 border-b border-white/10 pb-3">
            {TABS.map(({ id, label }) => (
              <button
                key={id}
                type="button"
                onClick={() => setTab(id)}
                className={`rounded-lg px-4 py-2 text-sm font-medium transition ${
                  tab === id
                    ? "bg-white/15 text-white ring-1 ring-emerald-400/40"
                    : "bg-white/5 text-gray-300 hover:bg-white/10"
                }`}
              >
                {label}
              </button>
            ))}
          </div>

          {listError ? (
            <div className="rounded-lg border border-red-400/35 bg-red-500/10 px-4 py-3 text-sm text-red-100">
              {listError}
            </div>
          ) : null}

          <div className="rounded-xl border border-white/10 bg-white/5">
            {loading ? (
              <p className="p-6 text-sm text-gray-400">Loading…</p>
            ) : rows.length === 0 ? (
              <p className="p-6 text-sm text-gray-500">No {tab === "all" ? "" : tab} payout requests.</p>
            ) : (
              <ul className="divide-y divide-white/10">
                {rows.map((row) => (
                  <li key={row.id}>
                    <button
                      type="button"
                      onClick={() => openDetail(row)}
                      className="flex w-full flex-col gap-1 px-4 py-4 text-left transition hover:bg-white/5 sm:flex-row sm:items-center sm:justify-between"
                    >
                      <div className="min-w-0">
                        <p className="truncate font-medium text-white">{userLabel(row)}</p>
                        <p className="truncate text-xs text-gray-500 font-mono">{row.user_id}</p>
                      </div>
                      <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-gray-400">
                        <span className="font-semibold tabular-nums text-emerald-200">${formatMoney(row.amount)}</span>
                        <span
                          className={`rounded-full border px-2 py-0.5 text-[10px] font-medium uppercase ${statusBadgeClass(row.status)}`}
                        >
                          {row.status}
                        </span>
                        <span>{formatTs(row.requested_at)}</span>
                        <span className="font-mono text-blue-200/90">
                          {row.affiliate_code || row.profile_referral_code || "—"}
                        </span>
                      </div>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>
      </div>

      {selected ? (
        <div className="fixed inset-0 z-[90] flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm">
          <div
            className="max-h-[92vh] w-full max-w-lg overflow-y-auto rounded-2xl border border-white/10 bg-[#152238] p-6 text-white shadow-2xl"
            role="dialog"
            aria-modal="true"
          >
            <div className="flex items-start justify-between gap-3">
              <div>
                <h2 className="text-lg font-semibold text-emerald-300">Payout request</h2>
                <p className="mt-1 text-xs text-gray-400">{userLabel(selected)}</p>
              </div>
              <button
                type="button"
                onClick={() => closeDetail()}
                className="rounded-lg bg-white/10 px-3 py-1 text-sm hover:bg-white/20"
              >
                Close
              </button>
            </div>

            <dl className="mt-4 space-y-3 text-sm">
              <div>
                <dt className="text-xs text-gray-500">Request ID</dt>
                <dd className="break-all font-mono text-xs text-gray-300">{selected.id}</dd>
              </div>
              <div>
                <dt className="text-xs text-gray-500">User ID</dt>
                <dd className="break-all font-mono text-xs text-gray-300">{selected.user_id}</dd>
              </div>
              <div>
                <dt className="text-xs text-gray-500">Affiliate code</dt>
                <dd className="font-mono text-emerald-200">
                  {selected.affiliate_code || selected.profile_referral_code || "—"}
                </dd>
              </div>
              <div className="grid gap-3 sm:grid-cols-2">
                <div>
                  <dt className="text-xs text-gray-500">Username</dt>
                  <dd className="text-gray-200">{selected.username || "—"}</dd>
                </div>
                <div>
                  <dt className="text-xs text-gray-500">Name</dt>
                  <dd className="text-gray-200">{selected.name || "—"}</dd>
                </div>
              </div>
              {selected.referral_earnings != null && Number.isFinite(selected.referral_earnings) ? (
                <div>
                  <dt className="text-xs text-gray-500">Recorded referral earnings (profile)</dt>
                  <dd className="tabular-nums text-emerald-200">${formatMoney(selected.referral_earnings)}</dd>
                </div>
              ) : null}
              <div>
                <dt className="text-xs text-gray-500">Amount</dt>
                <dd className="text-xl font-semibold tabular-nums text-white">${formatMoney(selected.amount)}</dd>
              </div>
              <div>
                <dt className="text-xs text-gray-500">Status</dt>
                <dd>
                  <span
                    className={`inline-block rounded-full border px-2.5 py-0.5 text-xs font-medium uppercase ${statusBadgeClass(selected.status)}`}
                  >
                    {selected.status}
                  </span>
                </dd>
              </div>
              <div>
                <dt className="text-xs text-gray-500">Requested</dt>
                <dd className="text-xs text-gray-400">{formatTs(selected.requested_at)}</dd>
              </div>
              <div>
                <dt className="text-xs text-gray-500">Reviewed</dt>
                <dd className="text-xs text-gray-400">{formatTs(selected.reviewed_at)}</dd>
              </div>
              <div>
                <dt className="text-xs text-gray-500">Paid</dt>
                <dd className="text-xs text-gray-400">{formatTs(selected.paid_at)}</dd>
              </div>
              <div>
                <dt className="text-xs text-gray-500">Stripe transfer</dt>
                <dd className="break-all font-mono text-xs text-gray-300">
                  {selected.stripe_transfer_id || selected.payout_reference || "—"}
                </dd>
                {selected.status === "paid" && (selected.stripe_transfer_id || selected.payout_reference) ? (
                  <p className="mt-1 text-xs text-gray-500">
                    Bank deposit runs on Stripe&apos;s payout schedule for the connected account (not instant from
                    this app).
                  </p>
                ) : null}
              </div>
            </dl>

            <div className="mt-6 space-y-3 border-t border-white/10 pt-4">
              <label className="block">
                <span className="text-xs text-gray-400">Admin notes</span>
                <textarea
                  value={notesDraft}
                  onChange={(e) => setNotesDraft(e.target.value)}
                  disabled={actionBusy}
                  rows={3}
                  className="mt-1 w-full resize-none rounded-lg border border-white/15 bg-[#0f172a]/80 px-3 py-2 text-sm text-white placeholder:text-gray-600 focus:border-emerald-500/50 focus:outline-none focus:ring-1 focus:ring-emerald-500/40 disabled:opacity-50"
                  placeholder="Internal notes for this request"
                />
              </label>
              {selected.status === "approved" ? (
                <p className="text-xs text-gray-500">
                  Mark paid sends funds to the affiliate&apos;s Stripe connected account via a Transfer. Stripe
                  handles paying out to their bank on its usual schedule.
                </p>
              ) : null}

              {actionError ? (
                <p className="rounded-lg border border-red-400/40 bg-red-500/15 px-3 py-2 text-xs text-red-100">
                  {actionError}
                </p>
              ) : null}

              <div className="flex flex-wrap gap-2 pt-2">
                {selected.status === "pending" ? (
                  <>
                    <button
                      type="button"
                      disabled={actionBusy}
                      onClick={() => void handleApprove()}
                      className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:bg-blue-500"
                    >
                      Approve
                    </button>
                    <button
                      type="button"
                      disabled={actionBusy}
                      onClick={() => void handleReject()}
                      className="rounded-lg border border-red-400/50 bg-red-500/15 px-4 py-2 text-sm font-semibold text-red-100 hover:bg-red-500/25 disabled:opacity-50"
                    >
                      Reject
                    </button>
                  </>
                ) : null}
                {selected.status === "approved" ? (
                  <button
                    type="button"
                    disabled={actionBusy}
                    onClick={() => void handleMarkPaid()}
                    className="rounded-lg bg-gradient-to-r from-violet-500 to-emerald-600 px-4 py-2 text-sm font-semibold disabled:opacity-50"
                  >
                    {actionBusy ? "Sending Stripe transfer…" : "Mark paid (Stripe)"}
                  </button>
                ) : null}
              </div>
              {selected.status === "paid" || selected.status === "rejected" ? (
                <p className="text-xs text-gray-500">
                  This request is closed. Use Refresh after any external DB changes.
                </p>
              ) : null}
            </div>
          </div>
        </div>
      ) : null}
    </>
  )
}
