"use client"

import Link from "next/link"
import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Navbar from "@/app/components/Navbar"
import AffiliatePayoutRequestModal from "@/app/components/AffiliatePayoutRequestModal"
import {
  estimateEarningsFromReferralCount,
  payoutEarningsBase,
} from "@/lib/affiliateEarnings"
import {
  fetchMyAffiliatePayoutRequests,
  insertAffiliatePayoutRequest,
  type AffiliatePayoutRequestRow,
  type AffiliatePayoutStatus,
} from "@/lib/affiliatePayoutRequests"
import { supabase } from "@/lib/supabaseClient"

type MeProfile = {
  id: string
  username?: string | null
  name?: string | null
  referral_code?: string | null
  referral_earnings?: number | string | null
}

type AffiliateRowBrief = {
  id: string
  code: string | null
}

function formatMoney(n: number): string {
  return n.toFixed(2)
}

function formatTs(iso: string | null | undefined): string {
  if (!iso) return "—"
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return "—"
  return d.toLocaleString()
}

function statusBadgeClasses(status: AffiliatePayoutStatus): string {
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

function PayoutRequestCard({ row }: { row: AffiliatePayoutRequestRow }) {
  return (
    <div className="rounded-xl border border-white/10 bg-white/5 px-4 py-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="text-lg font-semibold tabular-nums text-white">${formatMoney(row.amount)}</span>
        <span
          className={`rounded-full border px-2.5 py-0.5 text-xs font-medium uppercase tracking-wide ${statusBadgeClasses(row.status)}`}
        >
          {row.status}
        </span>
      </div>
      <dl className="mt-2 grid gap-1 text-xs text-gray-400 sm:grid-cols-2">
        <div>
          <dt className="inline text-gray-500">Requested </dt>
          <dd className="inline text-gray-300">{formatTs(row.requested_at)}</dd>
        </div>
        <div>
          <dt className="inline text-gray-500">Paid </dt>
          <dd className="inline text-gray-300">{formatTs(row.paid_at)}</dd>
        </div>
      </dl>
      {row.status === "rejected" && row.admin_notes?.trim() ? (
        <p className="mt-2 border-t border-white/10 pt-2 text-xs text-gray-400">
          <span className="text-gray-500">Note: </span>
          {row.admin_notes.trim()}
        </p>
      ) : null}
    </div>
  )
}

export default function AffiliatePayoutsPage() {
  const router = useRouter()
  const [loading, setLoading] = useState(true)
  const [referralCode, setReferralCode] = useState<string | null>(null)
  const [referralCount, setReferralCount] = useState(0)
  const [recordedEarnings, setRecordedEarnings] = useState<number | null>(null)
  const [affiliateRowId, setAffiliateRowId] = useState<string | null>(null)
  const [payoutRows, setPayoutRows] = useState<AffiliatePayoutRequestRow[]>([])
  const [modalOpen, setModalOpen] = useState(false)
  const [successBanner, setSuccessBanner] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)

    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (!user) {
      setLoading(false)
      router.push("/login")
      return
    }

    const [profileRes, affRes, payoutsRes] = await Promise.all([
      supabase
        .from("profiles")
        .select("id, username, name, referral_code, referral_earnings")
        .eq("id", user.id)
        .maybeSingle(),
      supabase.from("affiliates").select("id, code").eq("user_id", user.id).maybeSingle(),
      fetchMyAffiliatePayoutRequests(supabase, user.id),
    ])

    const profile = profileRes.data as MeProfile | null
    const affRow = affRes.data as AffiliateRowBrief | null

    const profileCode =
      profile?.referral_code != null ? String(profile.referral_code).trim() : ""
    const affiliateCode =
      affRow?.code != null ? String(affRow.code).trim() : ""
    /** Shown everywhere we previously used `referralCode` — profile wins, then `affiliates.code`. */
    const effectiveReferralCode = profileCode || affiliateCode || null

    let recordedEarningsParsed: number | null = null
    if (profile != null && profile.referral_earnings != null && profile.referral_earnings !== "") {
      const n = Number(profile.referral_earnings)
      if (Number.isFinite(n)) recordedEarningsParsed = n
    }

    let referralCountResolved = 0
    if (effectiveReferralCode) {
      const { count, error: countErr } = await supabase
        .from("profiles")
        .select("id", { count: "exact", head: true })
        .eq("referred_by", effectiveReferralCode)
      if (!countErr && count != null) referralCountResolved = count
    }

    const payoutRowsSafe = payoutsRes.error ? [] : payoutsRes.rows

    setReferralCode(effectiveReferralCode)
    setReferralCount(referralCountResolved)
    setRecordedEarnings(recordedEarningsParsed)
    setAffiliateRowId(affRow?.id != null ? String(affRow.id) : null)
    setPayoutRows(payoutRowsSafe)
    setLoading(false)

    if (process.env.NODE_ENV === "development") {
      let reservedPre = 0
      let pendingPre = false
      for (const r of payoutRowsSafe) {
        if (r.status === "pending") {
          pendingPre = true
          reservedPre += r.amount
        } else if (r.status === "approved") {
          reservedPre += r.amount
        }
      }
      const earningsBasePre = payoutEarningsBase(recordedEarningsParsed, referralCountResolved)
      const availablePre = Math.max(
        0,
        Math.round((earningsBasePre - reservedPre) * 100) / 100
      )
      const canRequestPre =
        Boolean(affRow?.id) && !pendingPre && availablePre > 0.009
      const isActiveAffiliatePre = Boolean(affRow?.id || effectiveReferralCode)

      console.debug("[payouts] profile fetch", {
        data: profileRes.data,
        error: profileRes.error,
      })
      console.debug("[payouts] affiliate fetch", {
        data: affRes.data,
        error: affRes.error,
      })
      console.debug("[payouts] payout requests fetch", {
        rowCount: payoutRowsSafe.length,
        error: payoutsRes.error,
      })
      console.debug("[payouts] eligibility", {
        isActiveAffiliate: isActiveAffiliatePre,
        canRequestPayout: canRequestPre,
        affiliateRowId: affRow?.id ?? null,
        effectiveReferralCode,
        profileCodePresent: Boolean(profileCode),
        affiliateCodePresent: Boolean(affiliateCode),
        hasPendingRequest: pendingPre,
        availableToRequest: availablePre,
      })
    }
  }, [router])

  useEffect(() => {
    void load()
  }, [load])

  const estimatedEarnings = useMemo(
    () => estimateEarningsFromReferralCount(referralCount),
    [referralCount]
  )

  const earningsBase = useMemo(
    () => payoutEarningsBase(recordedEarnings, referralCount),
    [recordedEarnings, referralCount]
  )

  const { reservedAmount, availableToRequest, hasPending } = useMemo(() => {
    let reserved = 0
    let pending = false
    for (const r of payoutRows) {
      if (r.status === "pending") {
        pending = true
        reserved += r.amount
      } else if (r.status === "approved") {
        reserved += r.amount
      }
    }
    const avail = Math.max(0, Math.round((earningsBase - reserved) * 100) / 100)
    return { reservedAmount: reserved, availableToRequest: avail, hasPending: pending }
  }, [payoutRows, earningsBase])

  const pendingList = payoutRows.filter((r) => r.status === "pending")
  const approvedList = payoutRows.filter((r) => r.status === "approved")
  const paidList = payoutRows.filter((r) => r.status === "paid")
  const rejectedList = payoutRows.filter((r) => r.status === "rejected")

  const isActiveAffiliate = Boolean(affiliateRowId || referralCode)

  const canRequestPayout = Boolean(
    affiliateRowId && !hasPending && availableToRequest > 0.009
  )

  async function handleSubmitRequest(amount: number): Promise<{ error: string | null }> {
    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user || !affiliateRowId) {
      return { error: "You must be an active affiliate to request a payout." }
    }
    if (hasPending) {
      return { error: "You already have a pending payout request." }
    }
    if (amount > availableToRequest + 0.001) {
      return { error: `Amount cannot exceed available balance (${availableToRequest.toFixed(2)}).` }
    }

    const { error } = await insertAffiliatePayoutRequest(supabase, {
      user_id: user.id,
      affiliate_id: affiliateRowId,
      amount,
      status: "pending",
    })

    if (error) {
      return { error: error.message }
    }

    setSuccessBanner("Payout request submitted successfully")
    await load()
    return { error: null }
  }

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">
        <div className="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:p-10">
          <div className="mb-6 flex flex-wrap items-center justify-between gap-4">
            <div>
              <Link href="/affiliate" className="text-sm text-blue-300 hover:text-blue-200">
                ← Affiliate dashboard
              </Link>
              <h1 className="mt-2 text-2xl font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent sm:text-3xl">
                Payouts
              </h1>
              <p className="mt-1 text-sm text-gray-400">
                Request a payout from your affiliate earnings. Transfers are processed manually for now—no
                instant Stripe payouts yet.
              </p>
            </div>
            <button
              type="button"
              onClick={() => void load()}
              disabled={loading}
              className="rounded-lg bg-white/10 px-4 py-2 text-sm hover:bg-white/20 disabled:opacity-50"
            >
              {loading ? "Refreshing…" : "Refresh"}
            </button>
          </div>

          {successBanner ? (
            <div
              className="mb-6 flex flex-wrap items-center justify-between gap-2 rounded-lg border border-emerald-400/40 bg-emerald-500/15 px-4 py-3 text-sm text-emerald-50"
              role="status"
            >
              <span>{successBanner}</span>
              <button
                type="button"
                className="rounded-md bg-white/10 px-3 py-1 text-xs hover:bg-white/20"
                onClick={() => setSuccessBanner(null)}
              >
                Dismiss
              </button>
            </div>
          ) : null}

          {loading ? (
            <p className="text-sm text-gray-400">Loading…</p>
          ) : (
            <>
              <div className="mb-6 grid gap-4 sm:grid-cols-2">
                <div className="rounded-xl border border-white/10 bg-white/5 p-5 backdrop-blur-md">
                  <p className="text-sm text-gray-400">Earnings basis</p>
                  <p className="mt-1 text-2xl font-bold tabular-nums text-emerald-400">
                    ${formatMoney(earningsBase)}
                  </p>
                  <p className="mt-2 text-xs text-gray-500">
                    Uses your recorded referral balance when available; otherwise the same estimate as the
                    affiliate dashboard ({referralCount} referrals × commission).
                  </p>
                </div>
                <div className="rounded-xl border border-white/10 bg-white/5 p-5 backdrop-blur-md">
                  <p className="text-sm text-gray-400">Available to request</p>
                  <p className="mt-1 text-2xl font-bold tabular-nums text-white">
                    ${formatMoney(availableToRequest)}
                  </p>
                  <p className="mt-2 text-xs text-gray-500">
                    Pending and approved requests reserve{" "}
                    <span className="tabular-nums text-gray-400">${formatMoney(reservedAmount)}</span>.
                    Estimated (dashboard-style) total:{" "}
                    <span className="tabular-nums text-gray-400">${formatMoney(estimatedEarnings)}</span>.
                  </p>
                </div>
              </div>

              {!isActiveAffiliate ? (
                <div className="mb-8 rounded-xl border border-amber-500/35 bg-amber-500/10 px-4 py-4 text-sm text-amber-50">
                  You need an active affiliate referral code before you can request payouts.{" "}
                  <Link href="/affiliate" className="font-medium text-blue-300 underline hover:text-blue-200">
                    Open the Affiliate Dashboard
                  </Link>{" "}
                  to apply or finish setup.
                </div>
              ) : referralCode && !affiliateRowId ? (
                <div className="mb-8 rounded-xl border border-amber-500/35 bg-amber-500/10 px-4 py-4 text-sm text-amber-50">
                  Your affiliate profile isn&apos;t fully linked yet. Contact support or visit{" "}
                  <Link href="/affiliate" className="font-medium text-blue-300 underline hover:text-blue-200">
                    Affiliate Dashboard
                  </Link>{" "}
                  — payout requests unlock once your account is connected.
                </div>
              ) : null}

              {affiliateRowId && hasPending ? (
                <div className="mb-8 rounded-xl border border-amber-500/40 bg-amber-500/10 px-4 py-3 text-sm text-amber-100">
                  You already have a <strong>pending</strong> payout request. Submit another only after this
                  one is approved, paid, or rejected.
                </div>
              ) : null}

              <div className="mb-10 flex flex-wrap items-center gap-3">
                <button
                  type="button"
                  disabled={!canRequestPayout || loading}
                  onClick={() => setModalOpen(true)}
                  className="rounded-lg bg-gradient-to-r from-emerald-500 to-blue-500 px-5 py-2.5 text-sm font-semibold shadow-lg hover:opacity-95 disabled:opacity-50"
                >
                  Request payout
                </button>
                {!canRequestPayout && affiliateRowId ? (
                  <span className="text-xs text-gray-500">
                    {availableToRequest <= 0 && !hasPending
                      ? "Nothing available to request after reservations."
                      : null}
                  </span>
                ) : null}
              </div>

              <div className="space-y-10">
                {payoutRows.length === 0 ? (
                  <div className="rounded-xl border border-white/10 bg-white/5 p-10 text-center">
                    <p className="text-sm font-medium text-gray-300">No payout requests yet</p>
                    <p className="mt-2 text-sm text-gray-500">
                      When you submit a request, it will appear here with status updates.
                    </p>
                  </div>
                ) : null}

                {pendingList.length > 0 ? (
                  <section>
                    <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-blue-300">
                      Pending
                    </h2>
                    <div className="space-y-2">
                      {pendingList.map((row) => (
                        <PayoutRequestCard key={row.id} row={row} />
                      ))}
                    </div>
                  </section>
                ) : null}

                {approvedList.length > 0 ? (
                  <section>
                    <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-blue-300">
                      Approved (awaiting payout)
                    </h2>
                    <div className="space-y-2">
                      {approvedList.map((row) => (
                        <PayoutRequestCard key={row.id} row={row} />
                      ))}
                    </div>
                  </section>
                ) : null}

                {paidList.length > 0 ? (
                  <section>
                    <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-emerald-300/90">
                      Paid history
                    </h2>
                    <div className="space-y-2">
                      {paidList.map((row) => (
                        <PayoutRequestCard key={row.id} row={row} />
                      ))}
                    </div>
                  </section>
                ) : null}

                {rejectedList.length > 0 ? (
                  <section>
                    <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-red-300/90">
                      Rejected
                    </h2>
                    <div className="space-y-2">
                      {rejectedList.map((row) => (
                        <PayoutRequestCard key={row.id} row={row} />
                      ))}
                    </div>
                  </section>
                ) : null}
              </div>
            </>
          )}
        </div>
      </div>

      <AffiliatePayoutRequestModal
        open={modalOpen}
        onClose={() => setModalOpen(false)}
        availableAmount={availableToRequest}
        onSubmit={handleSubmitRequest}
      />
    </>
  )
}
