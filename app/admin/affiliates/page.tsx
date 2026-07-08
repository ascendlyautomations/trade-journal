"use client"

import Link from "next/link"
import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import {
  adminApproveAffiliateApplication,
  adminRejectAffiliateApplication,
} from "@/lib/affiliateAdmin"
import { getCurrentAdminCheckResult } from "@/lib/adminUsers"
import { type AffiliateApplicationRow } from "@/lib/affiliateApplication"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"
import { supabase } from "@/lib/supabaseClient"

type TabId = "pending" | "approved" | "rejected"

type ProfileBrief = {
  id: string
  username?: string | null
  name?: string | null
}

function formatTs(iso: string | null | undefined): string {
  if (!iso) return "—"
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return iso
  return d.toLocaleString()
}

function formatFollowers(v: number | null | undefined): string {
  if (v == null || typeof v !== "number" || Number.isNaN(v)) return "—"
  return v.toLocaleString()
}

function applicantProfile(row: AffiliateApplicationRow): ProfileBrief | null {
  const p = (row as AffiliateApplicationRow & { profiles?: ProfileBrief | ProfileBrief[] | null }).profiles
  if (Array.isArray(p)) return p[0] ?? null
  return p ?? null
}

function applicantLabel(row: AffiliateApplicationRow): string {
  const p = applicantProfile(row)
  const bits = [p?.username?.trim() || null, p?.name?.trim() || null].filter(Boolean)
  if (bits.length) return bits.join(" · ")
  return row.user_id.slice(0, 8) + "…"
}

function InlineSpinner({ className }: { className?: string }) {
  return (
    <svg
      className={`animate-spin ${className ?? "h-4 w-4 text-white"}`}
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      aria-hidden
    >
      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
      <path
        className="opacity-75"
        fill="currentColor"
        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
      />
    </svg>
  )
}

export default function AdminAffiliateApplicationsPage() {
  const router = useRouter()
  const [checking, setChecking] = useState(true)
  const [allowed, setAllowed] = useState(false)
  const [tab, setTab] = useState<TabId>("pending")
  const [rows, setRows] = useState<AffiliateApplicationRow[]>([])
  const [loading, setLoading] = useState(false)
  const [selected, setSelected] = useState<AffiliateApplicationRow | null>(null)
  const [pendingAction, setPendingAction] = useState<null | "approve" | "reject">(null)
  const [actionError, setActionError] = useState<string | null>(null)
  const [successBanner, setSuccessBanner] = useState<
    null | { message: string; variant: "success" | "neutral" }
  >(null)
  const [finalCodeOverride, setFinalCodeOverride] = useState("")
  const [stripePromoId, setStripePromoId] = useState("")
  const [rejectNotes, setRejectNotes] = useState("")
  const [affStripe, setAffStripe] = useState<{
    stripe_connected_account_id: string | null
    stripe_onboarding_complete: boolean
    stripe_payouts_enabled: boolean
  } | null>(null)

  const actionBusy = pendingAction !== null

  const fetchApplications = useCallback(async () => {
    if (!allowed) return
    setLoading(true)
    try {
      const params = new URLSearchParams({ status: tab })
      const res = await fetch(`/api/admin/affiliates/applications?${params}`, {
        credentials: "include",
        headers: {
          ...(await supabaseBearerHeaders()),
        },
      })
      const json = (await res.json()) as {
        applications?: unknown[]
        error?: string
      }
      if (!res.ok) {
        console.error("❌ Affiliate fetch error:", json?.error ?? res.statusText)
        setRows([])
        return
      }
      const list = (json.applications || []) as unknown as AffiliateApplicationRow[]
      setRows(list)
    } catch (e) {
      console.error("❌ Affiliate fetch error:", e)
      setRows([])
    } finally {
      setLoading(false)
    }
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
        setAllowed(true)
        setChecking(false)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [router])

  useEffect(() => {
    void fetchApplications()
  }, [fetchApplications])

  useEffect(() => {
    if (!selected?.user_id || selected.status !== "approved") {
      setAffStripe(null)
      return
    }
    let cancelled = false
    void supabase
      .from("affiliates")
      .select("stripe_connected_account_id, stripe_onboarding_complete, stripe_payouts_enabled")
      .eq("user_id", selected.user_id)
      .maybeSingle()
      .then(({ data, error }) => {
        if (cancelled) return
        if (error || !data) {
          setAffStripe(null)
          return
        }
        setAffStripe({
          stripe_connected_account_id:
            data.stripe_connected_account_id != null
              ? String(data.stripe_connected_account_id)
              : null,
          stripe_onboarding_complete: Boolean(data.stripe_onboarding_complete),
          stripe_payouts_enabled: Boolean(data.stripe_payouts_enabled),
        })
      })
    return () => {
      cancelled = true
    }
  }, [selected])

  function openDetail(row: AffiliateApplicationRow) {
    setSelected(row)
    setActionError(null)
    setSuccessBanner(null)
    setFinalCodeOverride("")
    setStripePromoId("")
    setRejectNotes("")
    setPendingAction(null)
  }

  function closeDetail() {
    setSelected(null)
    setActionError(null)
    setFinalCodeOverride("")
    setStripePromoId("")
    setRejectNotes("")
    setPendingAction(null)
  }

  const finalCodePreview = useMemo(() => {
    const o = finalCodeOverride.trim()
    if (o) return o.toUpperCase()
    const req = selected?.requested_code?.trim()
    if (req) return req.toUpperCase()
    return "— will be auto-generated from username + 3 digits"
  }, [finalCodeOverride, selected?.requested_code])

  async function handleApprove() {
    if (!selected?.id) return
    const promo = stripePromoId.trim()
    if (!promo) {
      setActionError("Stripe promo code ID is required to approve.")
      return
    }
    setPendingAction("approve")
    setActionError(null)
    const override = finalCodeOverride.trim()
    const { error } = await adminApproveAffiliateApplication(supabase, {
      applicationId: selected.id,
      adminCode: override ? override : null,
      stripePromo: promo,
    })
    setPendingAction(null)
    if (error) {
      setActionError(error.message)
      return
    }

    const approvedUserId = selected.user_id
    void (async () => {
      try {
        const res = await fetch("/api/admin/affiliates/provision-connect", {
          method: "POST",
          credentials: "include",
          headers: {
            "Content-Type": "application/json",
            ...(await supabaseBearerHeaders()),
          },
          body: JSON.stringify({ affiliateUserId: approvedUserId }),
        })
        if (!res.ok && process.env.NODE_ENV === "development") {
          const j = await res.json().catch(() => ({}))
          console.warn("[admin] provision-connect failed", res.status, j)
        }
      } catch (e) {
        if (process.env.NODE_ENV === "development") console.warn("[admin] provision-connect", e)
      }
    })()

    setSelected(null)
    setActionError(null)
    setFinalCodeOverride("")
    setStripePromoId("")
    setRejectNotes("")
    setTab("approved")
    setSuccessBanner({ message: "Affiliate approved successfully", variant: "success" })
    void fetchApplications()
  }

  async function handleReject() {
    if (!selected?.id) return
    setPendingAction("reject")
    setActionError(null)
    const notes = rejectNotes.trim()
    const { error } = await adminRejectAffiliateApplication(supabase, {
      applicationId: selected.id,
      adminNotes: notes ? notes : null,
    })
    setPendingAction(null)
    if (error) {
      setActionError(error.message)
      return
    }
    setSelected(null)
    setActionError(null)
    setFinalCodeOverride("")
    setStripePromoId("")
    setRejectNotes("")
    setTab("rejected")
    setSuccessBanner({ message: "Application rejected", variant: "neutral" })
    void fetchApplications()
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
                Affiliate applications
              </h1>
              <p className="mt-1 text-sm text-gray-400">
                Approve or reject applications. Approval requires a Stripe promo code ID; you can optionally
                override the final affiliate code.
              </p>
            </div>
          </div>

          {successBanner ? (
            <div
              className={
                successBanner.variant === "success"
                  ? "flex flex-wrap items-center justify-between gap-2 rounded-lg border border-emerald-400/40 bg-emerald-500/15 px-4 py-3 text-sm text-emerald-50"
                  : "flex flex-wrap items-center justify-between gap-2 rounded-lg border border-amber-400/35 bg-amber-500/10 px-4 py-3 text-sm text-amber-100"
              }
              role="status"
            >
              <span>{successBanner.message}</span>
              <button
                type="button"
                className="shrink-0 rounded-md bg-white/10 px-3 py-1 text-xs hover:bg-white/20"
                onClick={() => setSuccessBanner(null)}
              >
                Dismiss
              </button>
            </div>
          ) : null}

          <div className="flex flex-wrap gap-2 border-b border-white/10 pb-3">
            {(
              [
                ["pending", "Pending"],
                ["approved", "Approved"],
                ["rejected", "Rejected"],
              ] as const
            ).map(([id, label]) => (
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

          <div className="rounded-xl border border-white/10 bg-white/5">
            {loading ? (
              <p className="p-6 text-sm text-gray-400">Loading…</p>
            ) : rows.length === 0 ? (
              <p className="p-6 text-sm text-gray-500">No {tab} applications.</p>
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
                        <p className="truncate font-medium text-white">{applicantLabel(row)}</p>
                        <p className="truncate text-xs text-gray-400">
                          {(applicantProfile(row)?.username && `@${applicantProfile(row)!.username}`) || "—"}
                        </p>
                      </div>
                      <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-gray-400">
                        <span className="font-mono text-blue-200/90">{row.social_handle?.trim() || "—"}</span>
                        <span>{formatFollowers(row.followers)}</span>
                        <span className="font-mono text-emerald-200/90">
                          req: {row.requested_code?.trim() || "—"}
                        </span>
                        <span>{formatTs(row.created_at)}</span>
                        <span className="uppercase text-gray-500">{row.status}</span>
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
                <h2 className="text-lg font-semibold text-emerald-300">Application</h2>
                <p className="mt-1 text-xs text-gray-400">{applicantLabel(selected)}</p>
              </div>
              <button
                type="button"
                onClick={() => closeDetail()}
                className="rounded-lg bg-white/10 px-3 py-1 text-sm hover:bg-white/20"
              >
                Close
              </button>
            </div>

            <div className="mt-4 rounded-xl border border-white/10 bg-white/[0.07] p-4">
              <p className="text-xs font-medium uppercase tracking-wide text-gray-500">Social presence</p>
              <p className="mt-1 break-all font-mono text-lg font-semibold text-blue-200">
                {selected.social_handle?.trim() || "—"}
              </p>
              <p className="mt-3 text-sm">
                <span className="text-gray-500">Followers </span>
                <span className="font-semibold text-white">{formatFollowers(selected.followers)}</span>
              </p>
            </div>

            <dl className="mt-4 space-y-3 text-sm">
              <div>
                <dt className="text-xs text-gray-500">Username</dt>
                <dd className="text-gray-200">{applicantProfile(selected)?.username || "—"}</dd>
              </div>
              <div>
                <dt className="text-xs text-gray-500">Name</dt>
                <dd className="text-gray-200">{applicantProfile(selected)?.name || "—"}</dd>
              </div>
              <div>
                <dt className="text-xs text-gray-500">Requested affiliate code</dt>
                <dd className="font-mono text-emerald-200">
                  {selected.requested_code?.trim() || "— (none — auto on approve if no override)"}
                </dd>
              </div>
              <div>
                <dt className="text-xs text-gray-500">Created</dt>
                <dd className="text-xs text-gray-400">{formatTs(selected.created_at)}</dd>
              </div>
              {selected.status !== "pending" ? (
                <div>
                  <dt className="text-xs text-gray-500">Reviewed</dt>
                  <dd className="text-xs text-gray-400">{formatTs(selected.reviewed_at)}</dd>
                </div>
              ) : null}
            </dl>

            {selected.status === "approved" ? (
              <div className="mt-4 rounded-lg border border-white/10 bg-white/5 px-3 py-3 text-xs">
                <p className="font-medium text-gray-300">Stripe payout setup</p>
                {affStripe == null ? (
                  <p className="mt-1 text-gray-500">Loading…</p>
                ) : (
                  <dl className="mt-2 space-y-1.5 text-gray-300">
                    <div>
                      <span className="text-gray-500">Connected account ID </span>
                      <span className="break-all font-mono text-gray-200">
                        {affStripe.stripe_connected_account_id || "—"}
                      </span>
                    </div>
                    <div>
                      <span className="text-gray-500">Onboarding complete </span>
                      {affStripe.stripe_onboarding_complete ? (
                        <span className="text-emerald-300">Yes</span>
                      ) : (
                        <span className="text-amber-200">No</span>
                      )}
                    </div>
                    <div>
                      <span className="text-gray-500">Payouts enabled </span>
                      {affStripe.stripe_payouts_enabled ? (
                        <span className="text-emerald-300">Yes</span>
                      ) : (
                        <span className="text-amber-200">No</span>
                      )}
                    </div>
                  </dl>
                )}
              </div>
            ) : null}

            {selected.status === "pending" ? (
              <div className="mt-6 space-y-4 border-t border-white/10 pt-4">
                <div className="rounded-lg border border-emerald-500/30 bg-emerald-500/10 px-3 py-2">
                  <p className="text-xs text-gray-400">Final code preview</p>
                  <p className="mt-1 font-mono text-sm font-medium text-emerald-200">{finalCodePreview}</p>
                </div>

                {actionError ? (
                  <p className="rounded-lg border border-red-400/40 bg-red-500/15 px-3 py-2 text-xs whitespace-pre-wrap text-red-100">
                    {actionError}
                  </p>
                ) : null}

                <div className="space-y-3">
                  <label className="block">
                    <span className="text-xs text-gray-400">Final affiliate code (optional override)</span>
                    <input
                      type="text"
                      value={finalCodeOverride}
                      onChange={(e) => setFinalCodeOverride(e.target.value)}
                      disabled={actionBusy}
                      className="mt-1 w-full rounded-lg border border-white/15 bg-[#0f172a]/80 px-3 py-2 font-mono text-sm text-white placeholder:text-gray-600 focus:border-emerald-500/50 focus:outline-none focus:ring-1 focus:ring-emerald-500/40 disabled:opacity-50"
                      placeholder="Leave blank to use requested code or auto-generate"
                      autoComplete="off"
                    />
                  </label>
                  <label className="block">
                    <span className="text-xs text-gray-400">Stripe promo code ID (required for approval)</span>
                    <input
                      type="text"
                      value={stripePromoId}
                      onChange={(e) => setStripePromoId(e.target.value)}
                      disabled={actionBusy}
                      className="mt-1 w-full rounded-lg border border-white/15 bg-[#0f172a]/80 px-3 py-2 font-mono text-sm text-white placeholder:text-gray-600 focus:border-emerald-500/50 focus:outline-none focus:ring-1 focus:ring-emerald-500/40 disabled:opacity-50"
                      placeholder="promo_…"
                      autoComplete="off"
                    />
                  </label>
                  <label className="block">
                    <span className="text-xs text-gray-400">Admin notes (optional, stored if you reject)</span>
                    <textarea
                      value={rejectNotes}
                      onChange={(e) => setRejectNotes(e.target.value)}
                      disabled={actionBusy}
                      rows={2}
                      className="mt-1 w-full resize-none rounded-lg border border-white/15 bg-[#0f172a]/80 px-3 py-2 text-sm text-white placeholder:text-gray-600 focus:border-emerald-500/50 focus:outline-none focus:ring-1 focus:ring-emerald-500/40 disabled:opacity-50"
                      placeholder="Visible on the application when rejected"
                    />
                  </label>
                </div>

                <div className="flex flex-wrap gap-2 pt-1">
                  <button
                    type="button"
                    disabled={actionBusy}
                    onClick={() => void handleApprove()}
                    className="inline-flex items-center justify-center gap-2 rounded-lg bg-blue-500 px-5 py-2 text-sm font-semibold text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:bg-blue-500"
                  >
                    {pendingAction === "approve" ? (
                      <InlineSpinner className="h-4 w-4 text-white" />
                    ) : null}
                    Approve
                  </button>
                  <button
                    type="button"
                    disabled={actionBusy}
                    onClick={() => void handleReject()}
                    className="inline-flex items-center justify-center gap-2 rounded-lg border border-red-400/50 bg-red-500/15 px-5 py-2 text-sm font-semibold text-red-100 hover:bg-red-500/25 disabled:opacity-50"
                  >
                    {pendingAction === "reject" ? (
                      <InlineSpinner className="h-4 w-4 text-red-100" />
                    ) : null}
                    Reject
                  </button>
                </div>
              </div>
            ) : null}
          </div>
        </div>
      ) : null}
    </>
  )
}
