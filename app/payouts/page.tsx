"use client"

import Link from "next/link"
import { useCallback, useEffect, useLayoutEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Navbar from "@/app/components/Navbar"
import AffiliatePayoutSetupCard from "@/app/components/AffiliatePayoutSetupCard"
import AffiliatePayoutRequestModal from "@/app/components/AffiliatePayoutRequestModal"
import {
  AFFILIATE_CONNECT_SELECT,
  isAffiliatePayoutSetupComplete,
  parseAffiliateConnectRow,
  type AffiliateConnectRow,
} from "@/lib/affiliateStripeConnect"
import { AFFILIATE_PER_REFERRAL_EARNINGS } from "@/lib/affiliateEarnings"
import {
  fetchAffiliatePayoutBalance,
  type AffiliatePayoutBalance,
} from "@/lib/affiliatePayoutBalance"
import {
  fetchMyAffiliatePayoutRequests,
  insertAffiliatePayoutRequest,
  type AffiliatePayoutRequestRow,
  type AffiliatePayoutStatus,
} from "@/lib/affiliatePayoutRequests"
import { supabase } from "@/lib/supabaseClient"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"

type MeProfile = {
  id: string
  username?: string | null
  name?: string | null
  referral_code?: string | null
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
  const [payoutBalance, setPayoutBalance] = useState<AffiliatePayoutBalance | null>(null)
  const [balanceRpcError, setBalanceRpcError] = useState<string | null>(null)
  const [affiliateRowId, setAffiliateRowId] = useState<string | null>(null)
  const [affiliateConnectRow, setAffiliateConnectRow] = useState<AffiliateConnectRow | null>(null)
  const [payoutRows, setPayoutRows] = useState<AffiliatePayoutRequestRow[]>([])
  const [modalOpen, setModalOpen] = useState(false)
  const [successBanner, setSuccessBanner] = useState<string | null>(null)
  const [returnFromStripeSetup, setReturnFromStripeSetup] = useState(false)

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

    const [balRes, profileRes, affRes, payoutsRes] = await Promise.all([
      fetchAffiliatePayoutBalance(supabase, user.id),
      supabase
        .from("profiles")
        .select("id, username, name, referral_code")
        .eq("id", user.id)
        .maybeSingle(),
      supabase.from("affiliates").select(AFFILIATE_CONNECT_SELECT).eq("user_id", user.id).maybeSingle(),
      fetchMyAffiliatePayoutRequests(supabase, user.id),
    ])

    const profile = profileRes.data as MeProfile | null

    let connectRow: AffiliateConnectRow | null = null
    if (affRes.data && typeof affRes.data === "object") {
      connectRow = parseAffiliateConnectRow(affRes.data as Record<string, unknown>)
    }

    if (connectRow?.stripe_connected_account_id) {
      try {
        const syncRes = await fetch("/api/affiliates/connect/sync", {
          method: "POST",
          credentials: "include",
          headers: {
            ...(await supabaseBearerHeaders()),
          },
        })
        const sj = (await syncRes.json().catch(() => ({}))) as {
          affiliate?: AffiliateConnectRow | null
        }
        if (sj?.affiliate) connectRow = sj.affiliate
      } catch {
        // ignore
      }
    }

    setAffiliateConnectRow(connectRow)

    const profileCode =
      profile?.referral_code != null ? String(profile.referral_code).trim() : ""
    const affiliateCode =
      connectRow?.code != null ? String(connectRow.code).trim() : ""
    /** Shown everywhere we previously used `referralCode` — profile wins, then `affiliates.code`. */
    const effectiveReferralCode = profileCode || affiliateCode || null

    const payoutRowsSafe = payoutsRes.error ? [] : payoutsRes.rows

    setReferralCode(effectiveReferralCode)

    if (balRes.error) {
      setBalanceRpcError(balRes.error.message)
      setPayoutBalance(null)
    } else {
      setBalanceRpcError(null)
      setPayoutBalance(balRes.balance)
    }

    if (process.env.NODE_ENV === "development") {
      console.log("[payouts] affiliate_payout_balance raw RPC result", balRes.raw)
      console.log("[payouts] affiliate_payout_balance mapped for UI", balRes.balance)
    }

    setAffiliateRowId(connectRow?.id != null ? String(connectRow.id) : null)
    setPayoutRows(payoutRowsSafe)
    setLoading(false)
  }, [router])

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- page data load
    void load()
  }, [load])

  /* Stripe return URL lands with ?setup=return; strip param after showing banner */
  useLayoutEffect(() => {
    if (typeof window === "undefined") return
    const p = new URLSearchParams(window.location.search)
    if (p.get("setup") === "return") {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- client-only URL flag after Stripe redirect
      setReturnFromStripeSetup(true)
      window.history.replaceState({}, "", "/payouts")
    }
  }, [])

  const referralCountBalance = payoutBalance?.referralCount ?? 0
  const perReferralFromRpc = payoutBalance?.perReferralEarnings ?? AFFILIATE_PER_REFERRAL_EARNINGS
  const totalEarnings = payoutBalance?.totalEarnings ?? 0
  const totalPaidOut = payoutBalance?.totalPaid ?? 0
  const earningsSinceLastPayout = payoutBalance?.earningsSinceLastPayout ?? 0
  const availableToRequest = payoutBalance?.availableToRequest ?? 0
  const pendingReserved = payoutBalance?.pendingReserved ?? 0
  const approvedReserved = payoutBalance?.approvedReserved ?? 0
  /** Amounts treated as consumed from the lifetime pool (approved + paid requests). */
  const consumedApprovedAndPaid = Math.max(0, totalEarnings - earningsSinceLastPayout)
  const minimumPayout = payoutBalance?.minimumPayout ?? 100
  const rpcCanRequest = payoutBalance?.canRequest === true

  const hasPending = useMemo(
    () => payoutRows.some((r) => r.status === "pending"),
    [payoutRows]
  )

  const pendingList = payoutRows.filter((r) => r.status === "pending")
  const approvedList = payoutRows.filter((r) => r.status === "approved")
  const paidList = payoutRows.filter((r) => r.status === "paid")
  const rejectedList = payoutRows.filter((r) => r.status === "rejected")

  const isActiveAffiliate = Boolean(affiliateRowId || referralCode)

  const payoutSetupComplete = isAffiliatePayoutSetupComplete(affiliateConnectRow)

  const canRequestPayout = Boolean(
    affiliateRowId &&
      payoutSetupComplete &&
      !hasPending &&
      payoutBalance != null &&
      rpcCanRequest &&
      availableToRequest >= minimumPayout - 0.001
  )

  async function handleSubmitRequest(amount: number): Promise<{ error: string | null }> {
    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user || !affiliateRowId) {
      return { error: "You must be an active affiliate to request a payout." }
    }
    if (amount <= 0 || !Number.isFinite(amount)) {
      return { error: "Enter an amount greater than zero." }
    }

    const { balance: freshBal, error: balErr } = await fetchAffiliatePayoutBalance(supabase, user.id)
    if (balErr || !freshBal) {
      return { error: "Could not verify your available balance. Try again." }
    }

    const minReq = freshBal.minimumPayout > 0 ? freshBal.minimumPayout : 100
    if (freshBal.availableToRequest < minReq - 0.001 || !freshBal.canRequest) {
      return {
        error: `You need at least $${minReq.toFixed(0)} available to request a payout.`,
      }
    }

    if (amount < minReq - 0.001) {
      return { error: `Minimum payout request is $${minReq.toFixed(0)}.` }
    }

    const cap = freshBal.availableToRequest
    if (amount > cap + 0.001) {
      return { error: `Amount cannot exceed available to request (${cap.toFixed(2)}).` }
    }

    if (hasPending) {
      return { error: "You already have a pending payout request." }
    }
    if (!isAffiliatePayoutSetupComplete(affiliateConnectRow)) {
      return {
        error: "Complete Stripe payout setup on the Affiliate Dashboard before requesting a payout.",
      }
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
                Totals follow the affiliate earnings model (referrals × ${AFFILIATE_PER_REFERRAL_EARNINGS.toFixed(2)});
                payout request statuses in this app reserve or consume balance — not Stripe settlement timing.
                You need at least <strong className="text-gray-200">${minimumPayout.toFixed(0)}</strong>{" "}
                <span className="text-gray-500">available</span> before you can submit a payout request.
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

          {returnFromStripeSetup ? (
            <div className="mb-6 rounded-xl border border-emerald-500/35 bg-emerald-500/10 px-4 py-3 text-sm text-emerald-50">
              You&apos;re back from Stripe. Your payout setup status is updated below.
            </div>
          ) : null}

          {balanceRpcError ? (
            <div className="mb-6 rounded-xl border border-red-400/40 bg-red-500/15 px-4 py-3 text-sm text-red-100">
              Could not load payout balance ({balanceRpcError}). Try Refresh — if this persists, the payout balance
              function may need to be applied on the database.
            </div>
          ) : null}

          {affiliateRowId ? (
            <div className="mb-6">
              <AffiliatePayoutSetupCard affiliateConnect={affiliateConnectRow} show />
            </div>
          ) : null}

          {loading ? (
            <p className="text-sm text-gray-400">Loading…</p>
          ) : (
            <>
              <div className="mb-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
                <div className="rounded-xl border border-white/10 bg-white/5 p-5 backdrop-blur-md">
                  <p className="text-sm text-gray-400">Total earnings</p>
                  <p className="mt-1 text-2xl font-bold tabular-nums text-emerald-400">
                    ${formatMoney(totalEarnings)}
                  </p>
                  <p className="mt-1 text-xs text-gray-500">
                    {referralCountBalance} referrals × ${perReferralFromRpc.toFixed(2)} — matches the Affiliate
                    dashboard.
                  </p>
                  <p className="mt-2 border-t border-white/10 pt-2 text-xs text-gray-400">
                    Paid out via completed requests (status paid):{" "}
                    <span className="font-semibold tabular-nums text-gray-300">${formatMoney(totalPaidOut)}</span>
                  </p>
                </div>
                <div className="rounded-xl border border-white/10 bg-white/5 p-5 backdrop-blur-md">
                  <p className="text-sm text-gray-400">Earnings since last payout</p>
                  <p className="mt-1 text-2xl font-bold tabular-nums text-blue-300">
                    ${formatMoney(earningsSinceLastPayout)}
                  </p>
                  <p className="mt-2 text-xs text-gray-500">
                    Total earnings minus amounts on <strong className="text-gray-400">approved</strong> or{" "}
                    <strong className="text-gray-400">paid</strong> payout requests (${formatMoney(consumedApprovedAndPaid)}{" "}
                    consumed).
                  </p>
                </div>
                <div className="rounded-xl border border-white/10 bg-white/5 p-5 backdrop-blur-md">
                  <p className="text-sm text-gray-400">Available to request</p>
                  <p className="mt-1 text-2xl font-bold tabular-nums text-white">
                    ${formatMoney(availableToRequest)}
                  </p>
                  <p className="mt-2 text-xs text-gray-500">
                    Earnings since last payout (${formatMoney(earningsSinceLastPayout)}) minus{" "}
                    <strong className="text-gray-400">pending</strong> requests (${formatMoney(pendingReserved)}). Approved
                    (${formatMoney(approvedReserved)}) is already deducted in “earnings since last payout”.
                  </p>
                </div>
                <div className="rounded-xl border border-white/10 bg-white/5 p-5 backdrop-blur-md">
                  <p className="text-sm text-gray-400">Minimum payout</p>
                  <p className="mt-1 text-2xl font-bold tabular-nums text-amber-200">
                    ${formatMoney(minimumPayout)}
                  </p>
                  <p className="mt-2 text-xs text-gray-500">
                    You need at least this much <strong className="text-gray-300">available</strong> before the Request
                    payout button unlocks.
                  </p>
                </div>
              </div>

              {payoutBalance?.lastPaidAt ? (
                <p className="mb-6 text-xs text-gray-500">
                  Last paid payout request:{" "}
                  <span className="tabular-nums text-gray-400">{formatTs(payoutBalance.lastPaidAt)}</span>
                </p>
              ) : null}

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

              {affiliateRowId && isActiveAffiliate && !payoutSetupComplete ? (
                <div className="mb-8 rounded-xl border border-violet-500/35 bg-violet-500/10 px-4 py-3 text-sm text-violet-100">
                  Complete <strong className="text-white">Stripe payout setup</strong> before requesting a
                  payout.{" "}
                  <Link href="/affiliate" className="font-medium text-blue-300 underline hover:text-blue-200">
                    Open Affiliate Dashboard
                  </Link>{" "}
                  and use <span className="font-medium text-white">Complete payout setup</span>.
                </div>
              ) : null}

              {affiliateRowId && hasPending ? (
                <div className="mb-8 rounded-xl border border-amber-500/40 bg-amber-500/10 px-4 py-3 text-sm text-amber-100">
                  You already have a <strong>pending</strong> payout request. Submit another only after this
                  one is approved, paid, or rejected.
                </div>
              ) : null}

              {affiliateRowId &&
              isActiveAffiliate &&
              payoutSetupComplete &&
              !hasPending &&
              payoutBalance &&
              !rpcCanRequest &&
              availableToRequest < minimumPayout - 0.001 ? (
                <div className="mb-8 rounded-xl border border-amber-500/35 bg-amber-500/10 px-4 py-3 text-sm text-amber-50">
                  You need at least <strong className="text-white">${minimumPayout.toFixed(0)}</strong> available to
                  request a payout. You currently have{" "}
                  <span className="tabular-nums font-semibold text-white">${formatMoney(availableToRequest)}</span>{" "}
                  available — keep earning referrals until you reach the minimum.
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
                    {!payoutSetupComplete
                      ? "Finish Stripe payout setup on the Affiliate Dashboard first."
                      : balanceRpcError
                        ? "Fix balance loading to request a payout."
                        : hasPending
                          ? "Wait until your pending request is approved, paid, or rejected."
                          : payoutBalance && !rpcCanRequest && availableToRequest < minimumPayout - 0.001
                            ? `You need at least $${minimumPayout.toFixed(0)} available to request a payout.`
                            : payoutBalance && availableToRequest <= 0
                              ? pendingReserved > 0.001
                                ? `Nothing left to request — $${formatMoney(pendingReserved)} reserved by pending request(s).`
                                : `Nothing left to request — remaining balance is consumed by approved or paid requests.`
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
        minimumAmount={minimumPayout}
        onSubmit={handleSubmitRequest}
      />
    </>
  )
}
