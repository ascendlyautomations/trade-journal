"use client"

import Link from "next/link"
import { useCallback, useEffect, useLayoutEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { supabase } from "@/lib/supabaseClient"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import AffiliateApplyModal from "@/app/components/AffiliateApplyModal"
import AffiliatePayoutSetupCard from "@/app/components/AffiliatePayoutSetupCard"
import {
  COMMISSION_RATE,
  recordedAffiliateEarnings,
  resolveRecordedAffiliateEarnings,
} from "@/lib/affiliateEarnings"
import {
  type AffiliateConnectRow,
} from "@/lib/affiliateStripeConnect"
import { fetchLatestAffiliateApplication, type AffiliateApplicationRow } from "@/lib/affiliateApplication"
import {
  ensureAffiliateConnectLoaded,
} from "@/lib/affiliateDataRepository"
import { syncAffiliateConnectStatus } from "@/lib/affiliateConnectSyncClient"
import {
  classifyReferredSubscriberStatus,
  formatAffiliateReferralJoinDate,
  referredSubscriberStatusBadgeClass,
  referredSubscriberStatusLabel,
  referredSubscriberStatusOrder,
  sumCommissionByReferredUser,
  type ReferredSubscriberStatus,
} from "@/lib/affiliateReferredUserStatus"
import { AFFILIATE_PRIMARY_BUTTON_CLASS } from "@/lib/affiliateUi"
import {
  SkeletonAffiliateDashboardPage,
} from "@/app/components/ui/skeletons"
import { useUserProfile } from "@/lib/useUserProfile"
import { fetchSettingsProfileRow } from "@/lib/settingsProfileSync"
import { readSettingsProfileCache } from "@/lib/settingsProfileCache"

type MeProfile = {
  id: string
  referral_code?: string | null
  referral_earnings?: number | null
}

type ReferredProfileRow = {
  id: string
  username?: string | null
  avatar_url?: string | null
  created_at?: string | null
  subscription_status?: string | null
}

type ReferredUserDisplayRow = ReferredProfileRow & {
  status: ReferredSubscriberStatus
  commissionEarned: number
}

export default function AffiliateDashboard() {
  const router = useRouter()
  const { user, profile: contextProfile } = useUserProfile()
  const [loading, setLoading] = useState(true)
  const [latestApp, setLatestApp] = useState<AffiliateApplicationRow | null>(null)
  const [referralCode, setReferralCode] = useState<string | null>(null)
  const [recordedEarnings, setRecordedEarnings] = useState(0)
  const [referredProfiles, setReferredProfiles] = useState<ReferredProfileRow[]>([])
  const [commissionByUserId, setCommissionByUserId] = useState<Record<string, number>>({})
  const [copyDone, setCopyDone] = useState(false)
  const [showAffiliateModal, setShowAffiliateModal] = useState(false)
  const [affiliateConnect, setAffiliateConnect] = useState<AffiliateConnectRow | null>(null)
  const [returnFromStripe, setReturnFromStripe] = useState(false)
  const [baseUrl, setBaseUrl] = useState(
    process.env.NEXT_PUBLIC_BASE_URL || "http://localhost:3000"
  )

  const isPending = latestApp?.status === "pending"
  const applicationLocked = Boolean(isPending && latestApp?.has_edited)
  const hasAffiliateAccess = Boolean(referralCode && referralCode.length > 0)

  const applicationStatusLabel = useMemo(() => {
    if (!latestApp) return null
    return latestApp.status
  }, [latestApp])

  const load = useCallback(async () => {
    setLoading(true)

    if (!user) {
      setLoading(false)
      router.push("/login")
      return
    }

    const cachedProfile =
      readSettingsProfileCache(user.id) ??
      (await fetchSettingsProfileRow(supabase, user.id).catch(() => null))

    const [appRes, connectRowInitial] = await Promise.all([
      fetchLatestAffiliateApplication(supabase, user.id),
      ensureAffiliateConnectLoaded(supabase, user.id),
    ])

    setLatestApp(appRes)

    let connectRow = connectRowInitial

    if (connectRow?.stripe_connected_account_id) {
      const sync = await syncAffiliateConnectStatus(user.id)
      if (sync.affiliate) {
        connectRow = sync.affiliate
      } else if (!sync.ok && sync.error && process.env.NODE_ENV === "development") {
        console.warn("[affiliate dashboard] connect sync:", sync.error)
      }
    }

    setAffiliateConnect(connectRow)

    const profile = cachedProfile as MeProfile | null

    if (!profile && !contextProfile?.referral_code) {
      setReferralCode(null)
      setRecordedEarnings(0)
      setReferredProfiles([])
      setCommissionByUserId({})
      setLoading(false)
      return
    }

    const code =
      contextProfile?.referral_code != null
        ? String(contextProfile.referral_code).trim()
        : ""
    setReferralCode(code || null)

    let earnings = recordedAffiliateEarnings(profile?.referral_earnings)
    if (code && earnings === 0) {
      const { data: ledger } = await supabase
        .from("referrals")
        .select("amount_earned")
        .eq("referrer_user_id", user.id)
      earnings = resolveRecordedAffiliateEarnings(profile?.referral_earnings, ledger)
    }
    setRecordedEarnings(earnings)

    if (!code) {
      setRecordedEarnings(0)
      setReferredProfiles([])
      setCommissionByUserId({})
      setLoading(false)
      return
    }

    const [referredRes, ledgerRes] = await Promise.all([
      supabase
        .from("profiles")
        .select("id, username, avatar_url, created_at, subscription_status")
        .eq("referred_by", code),
      supabase
        .from("referrals")
        .select("referred_user_id, amount_earned")
        .eq("referrer_user_id", user.id),
    ])

    if (referredRes.error) {
      console.error(referredRes.error)
      setReferredProfiles([])
    } else {
      setReferredProfiles((referredRes.data as ReferredProfileRow[]) ?? [])
    }

    if (ledgerRes.error) {
      console.error("[affiliate dashboard] referrals ledger:", ledgerRes.error)
      setCommissionByUserId({})
    } else {
      const commissionMap = sumCommissionByReferredUser(ledgerRes.data)
      setCommissionByUserId(Object.fromEntries(commissionMap))
    }

    setLoading(false)
  }, [router, user, contextProfile?.referral_code])

  useEffect(() => {
    void load()
  }, [load])

  useLayoutEffect(() => {
    if (typeof window === "undefined") return
    const p = new URLSearchParams(window.location.search)
    const openApply = p.get("apply") === "true"
    const returningFromStripe =
      p.get("connect") === "return" || p.get("setup") === "return"

    if (returningFromStripe) {
      setReturnFromStripe(true)
    }
    if (openApply) {
      setShowAffiliateModal(true)
    }
    if (returningFromStripe || openApply) {
      window.history.replaceState({}, "", "/affiliate/dashboard")
    }
  }, [])

  useEffect(() => {
    if (typeof window !== "undefined") {
      setBaseUrl(window.location.origin)
    }
  }, [])

  const referralLink = referralCode ? `${baseUrl}?ref=${encodeURIComponent(referralCode)}` : ""

  const totalReferrals = referredProfiles.length

  const referredUserRows = useMemo((): ReferredUserDisplayRow[] => {
    return referredProfiles.map((profile) => ({
      ...profile,
      status: classifyReferredSubscriberStatus(profile.subscription_status),
      commissionEarned: commissionByUserId[profile.id] ?? 0,
    }))
  }, [commissionByUserId, referredProfiles])

  const sortedReferredUsers = useMemo(() => {
    return [...referredUserRows].sort((a, b) => {
      const statusDiff =
        referredSubscriberStatusOrder(a.status) - referredSubscriberStatusOrder(b.status)
      if (statusDiff !== 0) return statusDiff
      const aTime = a.created_at ? new Date(a.created_at).getTime() : 0
      const bTime = b.created_at ? new Date(b.created_at).getTime() : 0
      return bTime - aTime
    })
  }, [referredUserRows])

  const trialUserCount = useMemo(
    () => referredUserRows.filter((r) => r.status === "trial").length,
    [referredUserRows]
  )
  const activeSubscriberCount = useMemo(
    () => referredUserRows.filter((r) => r.status === "active").length,
    [referredUserRows]
  )
  const cancelledSubscriberCount = useMemo(
    () => referredUserRows.filter((r) => r.status === "cancelled").length,
    [referredUserRows]
  )

  async function copyLink() {
    if (!referralLink) return
    try {
      await navigator.clipboard.writeText(referralLink)
      setCopyDone(true)
      window.setTimeout(() => setCopyDone(false), 2000)
    } catch {
      alert("Could not copy link")
    }
  }

  async function afterModalSubmit() {
    setShowAffiliateModal(false)
    await load()
  }

  const showApplyCta =
    !referralCode && (!latestApp || latestApp.status === "rejected")

  const showPayoutSetupSection = Boolean(
    referralCode || latestApp?.status === "approved" || affiliateConnect?.id
  )

  const applyButtonLabel = applicationLocked
    ? "View Application"
    : isPending
      ? "View Application"
      : "Become an Affiliate"

  const applyButtonClassName = applicationLocked
    ? "rounded-lg bg-white/10 px-5 py-2.5 text-sm font-semibold text-white/60 hover:bg-white/15"
    : `${AFFILIATE_PRIMARY_BUTTON_CLASS} px-5 py-2.5`

  return (
    <>
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">
        <div className="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:p-10">
          {loading ? (
            <SkeletonAffiliateDashboardPage />
          ) : hasAffiliateAccess ? (
            <>
              <div className="mb-8 flex flex-wrap items-center justify-between gap-4">
                <h1 className="text-2xl font-bold text-blue-300 sm:text-3xl">
                  Affiliate Dashboard
                </h1>
                <div className="flex items-center gap-2">
                  {(showApplyCta || isPending) && (
                    <button
                      type="button"
                      onClick={() => setShowAffiliateModal(true)}
                      className={applyButtonClassName}
                    >
                      {applyButtonLabel}
                    </button>
                  )}
                  <Link href="/payouts" className={AFFILIATE_PRIMARY_BUTTON_CLASS}>
                    Payouts
                  </Link>
                  <button
                    type="button"
                    onClick={() => void load()}
                    disabled={loading}
                    className={AFFILIATE_PRIMARY_BUTTON_CLASS}
                  >
                    Refresh
                  </button>
                </div>
              </div>

              {applicationStatusLabel === "pending" && (
                <div className="mb-6 rounded-xl border border-amber-500/40 bg-amber-500/10 px-4 py-3 text-sm text-amber-100">
                  <p>
                    Your affiliate application is <strong>under review</strong>.
                    {!latestApp?.has_edited ? (
                      <>
                        {" "}
                        Use <strong>Edit Application</strong> once to change your answers before a decision
                        is made.
                      </>
                    ) : null}
                  </p>
                  {latestApp?.has_edited ? (
                    <p className="mt-2 text-xs text-amber-200/90">
                      You have already used your one edit.
                    </p>
                  ) : null}
                </div>
              )}

              {latestApp?.status === "rejected" && (
                <div className="mb-6 rounded-xl border border-red-500/35 bg-red-500/10 px-4 py-3 text-sm text-red-100">
                  Your previous application was <strong>not approved</strong>. You may submit a new
                  application when you&apos;re ready.
                </div>
              )}

              {referralCode && (
                <div className="mb-6 rounded-xl border border-emerald-500/40 bg-emerald-500/10 px-4 py-3 text-sm text-emerald-50">
                  You&apos;re set up as an affiliate. Share your link below. Your code is{" "}
                  <span className="font-mono font-semibold text-white">{referralCode}</span>.
                </div>
              )}

              {returnFromStripe ? (
                <div className="mb-6 rounded-xl border border-emerald-500/35 bg-emerald-500/10 px-4 py-3 text-sm text-emerald-50">
                  You&apos;re back from Stripe. Your payout setup status is updated below.
                </div>
              ) : null}

              <div className="mb-8 grid grid-cols-1 gap-4 sm:grid-cols-3">
                <div className="rounded-xl border border-white/10 bg-white/5 p-5 backdrop-blur-md">
                  <p className="text-sm text-gray-400">Total earnings</p>
                  <p className="mt-1 text-2xl font-bold text-emerald-400">
                    ${recordedEarnings.toFixed(2)}
                  </p>
                  <p className="mt-2 text-xs text-gray-400">
                    {Math.round(COMMISSION_RATE * 100)}% of paid TraxPro invoices, recorded from Stripe
                    commissions.
                  </p>
                </div>
                <div className="rounded-xl border border-white/10 bg-white/5 p-5 backdrop-blur-md">
                  <p className="text-sm text-gray-400">Total referrals</p>
                  <p className="mt-1 text-2xl font-bold text-white">{totalReferrals}</p>
                </div>
                <div className="rounded-xl border border-white/10 bg-white/5 p-5 backdrop-blur-md">
                  <p className="text-sm text-gray-400">Referral code</p>
                  <p className="mt-1 break-all text-sm font-bold text-blue-300">
                    {referralCode || "—"}
                  </p>
                </div>
              </div>

              <div className="mb-8 grid grid-cols-1 gap-4 sm:grid-cols-3">
                <div className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-5 backdrop-blur-md">
                  <p className="text-sm text-amber-100/80">Trial Users</p>
                  <p className="mt-1 text-2xl font-bold tabular-nums text-amber-200">
                    {trialUserCount}
                  </p>
                  <p className="mt-2 text-xs text-amber-100/60">
                    Referred users currently in a free trial, no commission yet.
                  </p>
                </div>
                <div className="rounded-xl border border-emerald-500/30 bg-emerald-500/10 p-5 backdrop-blur-md">
                  <p className="text-sm text-emerald-100/80">Active Subscribers</p>
                  <p className="mt-1 text-2xl font-bold tabular-nums text-emerald-200">
                    {activeSubscriberCount}
                  </p>
                  <p className="mt-2 text-xs text-emerald-100/60">
                    Paid subscribers who may be generating commissions.
                  </p>
                </div>
                <div className="rounded-xl border border-red-500/30 bg-red-500/10 p-5 backdrop-blur-md">
                  <p className="text-sm text-red-100/80">Cancelled Subscribers</p>
                  <p className="mt-1 text-2xl font-bold tabular-nums text-red-200">
                    {cancelledSubscriberCount}
                  </p>
                  <p className="mt-2 text-xs text-red-100/60">
                    Subscriptions ended or inactive, no future commissions.
                  </p>
                </div>
              </div>

              <div className="mb-8">
                <AffiliatePayoutSetupCard affiliateConnect={affiliateConnect} show={showPayoutSetupSection} />
              </div>

              <div className="mb-8 rounded-xl border border-white/10 bg-white/5 p-6 backdrop-blur-md">
                <h2 className="text-sm font-semibold uppercase tracking-wide text-blue-300">
                  Share your link
                </h2>
                <>
                  <p className="mt-1 text-xs text-gray-400">Your code</p>
                  <p className="mt-0.5 font-mono text-lg font-semibold text-white">{referralCode}</p>
                  <p className="mt-4 text-sm text-gray-400">Referral link</p>
                  <div className="mt-2 flex flex-col gap-2 sm:flex-row sm:items-center">
                    <input
                      readOnly
                      value={referralLink}
                      className="min-w-0 flex-1 rounded-lg border border-white/10 bg-[#0f172a] px-3 py-2 font-mono text-sm text-white"
                    />
                    <button
                      type="button"
                      onClick={() => void copyLink()}
                      className={`shrink-0 ${AFFILIATE_PRIMARY_BUTTON_CLASS}`}
                    >
                      {copyDone ? "Copied!" : "Copy"}
                    </button>
                  </div>
                </>
              </div>

              <div>
                <h2 className="mb-4 text-lg font-semibold text-blue-400">Referred users</h2>

                {sortedReferredUsers.length === 0 ? (
                  <p className="rounded-xl border border-white/10 bg-white/5 p-6 text-center text-sm text-gray-400">
                    You have no referrals yet.
                  </p>
                ) : (
                  <div className="space-y-3">
                    {sortedReferredUsers.map((u) => (
                      <div
                        key={u.id}
                        className="rounded-xl border border-white/10 bg-white/5 p-4 backdrop-blur-md"
                      >
                        <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                          <div className="flex min-w-0 items-center gap-3">
                            <ProfileAvatarImg src={u.avatar_url} className="h-10 w-10 shrink-0" />
                            <div className="min-w-0">
                              <p className="truncate font-medium text-white">
                                {u.username?.trim() || "User"}
                              </p>
                              <p className="mt-0.5 text-xs text-gray-400">
                                Joined {formatAffiliateReferralJoinDate(u.created_at)}
                              </p>
                            </div>
                          </div>
                          <div className="flex flex-wrap items-center gap-3 sm:justify-end">
                            <span
                              className={`rounded-full border px-2.5 py-0.5 text-xs font-medium ${referredSubscriberStatusBadgeClass(u.status)}`}
                            >
                              {referredSubscriberStatusLabel(u.status)}
                            </span>
                            <div className="text-right">
                              <p className="text-xs text-gray-400">Commission earned</p>
                              <p
                                className={`text-sm font-semibold tabular-nums ${
                                  u.commissionEarned > 0 ? "text-emerald-400" : "text-gray-400"
                                }`}
                              >
                                ${u.commissionEarned.toFixed(2)}
                              </p>
                            </div>
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </>
          ) : (
            <>
              <div className="mb-8">
                <h1 className="text-2xl font-bold text-blue-300 sm:text-3xl">
                  Become an Affiliate
                </h1>
                <p className="mt-2 max-w-2xl text-sm text-gray-300">
                  Join the TradeTraxs Affiliate Program and earn when traders you refer subscribe to TraxPro.
                </p>
              </div>

              {applicationStatusLabel === "pending" && (
                <div className="mb-6 rounded-xl border border-amber-500/40 bg-amber-500/10 px-4 py-3 text-sm text-amber-100">
                  <p>
                    Your affiliate application is <strong>under review</strong>.
                    {!latestApp?.has_edited ? (
                      <>
                        {" "}
                        Use <strong>Edit Application</strong> once to change your answers before a decision
                        is made.
                      </>
                    ) : null}
                  </p>
                  {latestApp?.has_edited ? (
                    <p className="mt-2 text-xs text-amber-200/90">
                      You have already used your one edit.
                    </p>
                  ) : null}
                </div>
              )}

              {latestApp?.status === "rejected" && (
                <div className="mb-6 rounded-xl border border-red-500/35 bg-red-500/10 px-4 py-3 text-sm text-red-100">
                  Your previous application was <strong>not approved</strong>. You may submit a new
                  application when you&apos;re ready.
                </div>
              )}

              {latestApp?.status === "approved" && (
                <div className="mb-6 rounded-xl border border-amber-500/35 bg-amber-500/10 px-4 py-3 text-sm text-amber-50">
                  You&apos;re approved. Add a requested code on your next application or contact support if
                  your referral code hasn&apos;t appeared yet.
                </div>
              )}

              <section className="mb-8 rounded-xl border border-white/10 bg-white/5 p-6 backdrop-blur-md sm:p-8">
                <h2 className="text-lg font-semibold text-white">TradeTraxs Affiliate Program</h2>
                <p className="mt-3 text-sm leading-relaxed text-gray-300">
                  Share TradeTraxs with your audience and earn commissions when referred traders upgrade to
                  TraxPro. Approved affiliates receive a personal referral link and code to track signups.
                </p>

                <ul className="mt-5 space-y-2 text-sm text-gray-300">
                  <li className="flex gap-2">
                    <span className="text-emerald-400" aria-hidden>
                      •
                    </span>
                    <span>Earn on qualified TraxPro subscriptions from your referrals</span>
                  </li>
                  <li className="flex gap-2">
                    <span className="text-emerald-400" aria-hidden>
                      •
                    </span>
                    <span>Personal referral link and code after approval</span>
                  </li>
                  <li className="flex gap-2">
                    <span className="text-emerald-400" aria-hidden>
                      •
                    </span>
                    <span>Dashboard to track referrals and request payouts</span>
                  </li>
                </ul>

                <div className="mt-6 rounded-lg border border-emerald-500/25 bg-emerald-500/10 px-4 py-3">
                  <p className="text-sm font-medium text-emerald-100">Commission</p>
                  <p className="mt-1 text-sm text-emerald-50/90">
                    Earn{" "}
                    <span className="font-semibold text-white">
                      {Math.round(COMMISSION_RATE * 100)}%
                    </span>{" "}
                    commission on each paid TraxPro subscription invoice from your referrals.
                  </p>
                </div>

                {(showApplyCta || isPending) && (
                  <div className="mt-6">
                    <button
                      type="button"
                      onClick={() => setShowAffiliateModal(true)}
                      className={applyButtonClassName}
                    >
                      {applyButtonLabel}
                    </button>
                  </div>
                )}
              </section>

              <section className="rounded-xl border border-white/10 bg-white/[0.03] p-6 backdrop-blur-md sm:p-8">
                <div className="flex items-start gap-4">
                  <div
                    className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full border border-white/10 bg-white/5 text-gray-400"
                    aria-hidden
                  >
                    <svg
                      className="h-5 w-5"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="1.75"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25Z"
                      />
                    </svg>
                  </div>
                  <div className="min-w-0">
                    <h2 className="text-lg font-semibold text-white/80">Affiliate Dashboard</h2>
                    <p className="mt-2 text-sm leading-relaxed text-gray-400">
                      Your affiliate dashboard will become available once your affiliate application has
                      been approved.
                    </p>
                  </div>
                </div>
              </section>
            </>
          )}
        </div>
      </div>

      <AffiliateApplyModal
        open={showAffiliateModal}
        onClose={() => setShowAffiliateModal(false)}
        onSubmit={() => afterModalSubmit()}
        prefillFrom={latestApp}
        title={applicationLocked ? "View application" : "Affiliate application"}
      />
    </>
  )
}
