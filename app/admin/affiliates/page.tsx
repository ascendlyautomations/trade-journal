"use client"

import Link from "next/link"
import { useCallback, useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Navbar from "@/app/components/Navbar"
import {
  adminApproveAffiliateApplication,
  adminRejectAffiliateApplication,
} from "@/lib/affiliateAdmin"
import { getCurrentAdminCheckResult } from "@/lib/adminUsers"
import type { AffiliateApplicationRow } from "@/lib/affiliateApplication"
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

function applicantLabel(
  row: AffiliateApplicationRow,
  profileByUser: Record<string, ProfileBrief>
): string {
  const p = profileByUser[row.user_id]
  const bits = [
    p?.username?.trim() || null,
    p?.name?.trim() || null,
    row.full_name?.trim() || null,
  ].filter(Boolean)
  if (bits.length) return bits.join(" · ")
  if (row.email?.trim()) return row.email.trim()
  return row.user_id.slice(0, 8) + "…"
}

export default function AdminAffiliateApplicationsPage() {
  const router = useRouter()
  const [checking, setChecking] = useState(true)
  const [allowed, setAllowed] = useState(false)
  const [tab, setTab] = useState<TabId>("pending")
  const [rows, setRows] = useState<AffiliateApplicationRow[]>([])
  const [profileByUser, setProfileByUser] = useState<Record<string, ProfileBrief>>({})
  const [loading, setLoading] = useState(false)
  const [selected, setSelected] = useState<AffiliateApplicationRow | null>(null)
  const [finalCode, setFinalCode] = useState("")
  const [stripePromoId, setStripePromoId] = useState("")
  const [adminNotes, setAdminNotes] = useState("")
  const [rejectNotes, setRejectNotes] = useState("")
  const [actionBusy, setActionBusy] = useState(false)

  const fetchApplications = useCallback(async () => {
    if (!allowed) return
    setLoading(true)
    const { data, error } = await supabase
      .from("affiliate_applications")
      .select("*")
      .eq("status", tab)
      .order("created_at", { ascending: false })

    if (error) {
      console.error("[admin-affiliates] fetch failed", error)
      setRows([])
      setProfileByUser({})
      setLoading(false)
      return
    }

    const list = (data || []) as unknown as AffiliateApplicationRow[]
    setRows(list)

    const ids = [...new Set(list.map((r) => r.user_id))]
    if (ids.length === 0) {
      setProfileByUser({})
      setLoading(false)
      return
    }

    const { data: profs, error: pErr } = await supabase
      .from("profiles")
      .select("id, username, name")
      .in("id", ids)

    if (pErr) {
      console.error("[admin-affiliates] profiles failed", pErr)
      setProfileByUser({})
    } else {
      const map: Record<string, ProfileBrief> = {}
      for (const p of (profs || []) as ProfileBrief[]) {
        map[p.id] = p
      }
      setProfileByUser(map)
    }

    setLoading(false)
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

  function openDetail(row: AffiliateApplicationRow) {
    setSelected(row)
    setFinalCode((row.requested_code || "").trim())
    setStripePromoId("")
    setAdminNotes("")
    setRejectNotes("")
  }

  async function handleApprove() {
    if (!selected?.id) return
    const code = finalCode.trim()
    if (!code) {
      alert("Enter the final affiliate code to assign.")
      return
    }
    setActionBusy(true)
    const { error } = await adminApproveAffiliateApplication(supabase, {
      applicationId: selected.id,
      finalCode: code,
      stripePromoCodeId: stripePromoId.trim() || null,
      adminNotes: adminNotes.trim() || null,
    })
    setActionBusy(false)
    if (error) {
      alert(error.message)
      return
    }
    setSelected(null)
    void fetchApplications()
  }

  async function handleReject() {
    if (!selected?.id) return
    setActionBusy(true)
    const { error } = await adminRejectAffiliateApplication(supabase, {
      applicationId: selected.id,
      adminNotes: rejectNotes.trim() || null,
    })
    setActionBusy(false)
    if (error) {
      alert(error.message)
      return
    }
    setSelected(null)
    void fetchApplications()
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
                Review applications, approve with a final code, or reject with notes.
              </p>
            </div>
          </div>

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
                        <p className="truncate font-medium text-white">
                          {applicantLabel(row, profileByUser)}
                        </p>
                        <p className="truncate text-xs text-gray-400">{row.email || "—"}</p>
                      </div>
                      <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-gray-400">
                        <span>{row.platform?.trim() || "—"}</span>
                        <span className="font-mono text-blue-200/90">{row.social_handle?.trim() || "—"}</span>
                        <span>{row.audience_size?.trim() || "—"}</span>
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
                <h2 className="text-lg font-semibold text-emerald-300">Application detail</h2>
                <p className="mt-1 text-xs text-gray-400">{applicantLabel(selected, profileByUser)}</p>
              </div>
              <button
                type="button"
                onClick={() => setSelected(null)}
                className="rounded-lg bg-white/10 px-3 py-1 text-sm hover:bg-white/20"
              >
                Close
              </button>
            </div>

            <dl className="mt-4 space-y-3 text-sm">
              <div>
                <dt className="text-xs text-gray-500">Email</dt>
                <dd className="text-gray-200">{selected.email || "—"}</dd>
              </div>
              <div>
                <dt className="text-xs text-gray-500">Platform</dt>
                <dd className="text-gray-200">{selected.platform?.trim() || "—"}</dd>
              </div>
              <div>
                <dt className="text-xs text-gray-500">Audience</dt>
                <dd className="text-gray-200">{selected.audience_size?.trim() || "—"}</dd>
              </div>
              <div>
                <dt className="text-xs text-gray-500">Social</dt>
                <dd className="font-mono text-gray-200">{selected.social_handle?.trim() || "—"}</dd>
              </div>
              <div>
                <dt className="text-xs text-gray-500">Why join</dt>
                <dd className="whitespace-pre-wrap text-gray-200">{selected.why_join?.trim() || "—"}</dd>
              </div>
              <div>
                <dt className="text-xs text-gray-500">Promotion plan</dt>
                <dd className="whitespace-pre-wrap text-gray-200">{selected.promo_plan?.trim() || "—"}</dd>
              </div>
              <div>
                <dt className="text-xs text-gray-500">Requested code</dt>
                <dd className="font-mono text-emerald-200">{selected.requested_code?.trim() || "—"}</dd>
              </div>
              {selected.status !== "pending" ? (
                <>
                  <div>
                    <dt className="text-xs text-gray-500">Approved code</dt>
                    <dd className="font-mono text-emerald-200">{selected.approved_code?.trim() || "—"}</dd>
                  </div>
                  <div>
                    <dt className="text-xs text-gray-500">Admin notes</dt>
                    <dd className="whitespace-pre-wrap text-gray-300">{selected.admin_notes?.trim() || "—"}</dd>
                  </div>
                  <div>
                    <dt className="text-xs text-gray-500">Reviewed</dt>
                    <dd className="text-xs text-gray-400">{formatTs(selected.reviewed_at)}</dd>
                  </div>
                </>
              ) : null}
            </dl>

            {selected.status === "pending" ? (
              <div className="mt-6 space-y-4 border-t border-white/10 pt-4">
                <div>
                  <label className="text-xs text-gray-400">Final affiliate code</label>
                  <input
                    value={finalCode}
                    onChange={(e) => setFinalCode(e.target.value.toUpperCase())}
                    className="mt-1 w-full rounded-lg border border-white/10 bg-[#0f172a] p-2.5 font-mono text-sm"
                    placeholder="REQUIRED"
                  />
                </div>
                <div>
                  <label className="text-xs text-gray-400">Stripe promo code ID (optional)</label>
                  <input
                    value={stripePromoId}
                    onChange={(e) => setStripePromoId(e.target.value)}
                    className="mt-1 w-full rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-sm"
                    placeholder="promo_…"
                  />
                </div>
                <div>
                  <label className="text-xs text-gray-400">Admin notes (optional)</label>
                  <textarea
                    value={adminNotes}
                    onChange={(e) => setAdminNotes(e.target.value)}
                    rows={2}
                    className="mt-1 w-full resize-none rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-sm"
                  />
                </div>
                <div className="flex flex-wrap gap-2">
                  <button
                    type="button"
                    disabled={actionBusy}
                    onClick={() => void handleApprove()}
                    className="rounded-lg bg-gradient-to-r from-emerald-500 to-blue-500 px-5 py-2 text-sm font-semibold disabled:opacity-50"
                  >
                    Approve
                  </button>
                </div>

                <div className="border-t border-white/10 pt-4">
                  <label className="text-xs text-gray-400">Reject — notes (optional)</label>
                  <textarea
                    value={rejectNotes}
                    onChange={(e) => setRejectNotes(e.target.value)}
                    rows={2}
                    className="mt-1 w-full resize-none rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-sm"
                  />
                  <button
                    type="button"
                    disabled={actionBusy}
                    onClick={() => void handleReject()}
                    className="mt-3 rounded-lg border border-red-400/50 bg-red-500/15 px-5 py-2 text-sm font-semibold text-red-100 hover:bg-red-500/25 disabled:opacity-50"
                  >
                    Reject application
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
