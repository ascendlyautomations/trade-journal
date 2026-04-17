"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { supabase } from "../../lib/supabaseClient"
import Navbar from "../components/Navbar"
import AffiliateApplyModal from "../components/AffiliateApplyModal"
import {
  fetchLatestAffiliateApplication,
  fetchPendingAffiliateApplication,
  type AffiliateApplicationRow,
} from "@/lib/affiliateApplication"

type MeProfile = {
  id: string
  referral_code?: string | null
  referral_count?: number | null
}

type ReferredUser = {
  id: string
  username?: string | null
  avatar_url?: string | null
  created_at?: string | null
}

export default function AffiliateDashboard() {
  const COMMISSION_RATE = 0.18
  const PLAN_PRICE = 15.99

  const router = useRouter()
  const [loading, setLoading] = useState(true)
  const [displayName, setDisplayName] = useState("")
  const [email, setEmail] = useState<string | null>(null)
  const [pendingApp, setPendingApp] = useState<AffiliateApplicationRow | null>(null)
  const [latestApp, setLatestApp] = useState<AffiliateApplicationRow | null>(null)
  const [referralCode, setReferralCode] = useState<string | null>(null)
  const [totalReferrals, setTotalReferrals] = useState(0)
  const [referredUsers, setReferredUsers] = useState<ReferredUser[]>([])
  const [copyDone, setCopyDone] = useState(false)
  const [showAffiliateModal, setShowAffiliateModal] = useState(false)
  const [baseUrl, setBaseUrl] = useState(
    process.env.NEXT_PUBLIC_BASE_URL || "http://localhost:3000"
  )

  const approvedByApplication = latestApp?.status === "approved"
  const hasAffiliateAccess = Boolean((referralCode && referralCode.length > 0) || approvedByApplication)

  const applicationStatusLabel = useMemo(() => {
    if (pendingApp) return "pending"
    if (!latestApp) return null
    return latestApp.status
  }, [pendingApp, latestApp])

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

    setEmail(user.email ?? null)

    const [profileRes, pendingRes, latestRes] = await Promise.all([
      supabase
        .from("profiles")
        .select("id, referral_code, referral_count, name")
        .eq("id", user.id)
        .single(),
      fetchPendingAffiliateApplication(supabase, user.id),
      fetchLatestAffiliateApplication(supabase, user.id),
    ])

    setPendingApp(pendingRes)
    setLatestApp(latestRes)

    const profile = profileRes.data as MeProfile | null
    const profErr = profileRes.error

    if (profErr || !profile) {
      console.error(profErr)
      setDisplayName("")
      setReferralCode(null)
      setTotalReferrals(0)
      setReferredUsers([])
      setLoading(false)
      return
    }

    const rawName = (profile as { name?: string }).name
    setDisplayName(typeof rawName === "string" ? rawName.trim() : "")

    const code =
      profile.referral_code != null ? String(profile.referral_code).trim() : ""
    setReferralCode(code || null)
    setTotalReferrals(Number(profile.referral_count) || 0)

    if (!code) {
      setReferredUsers([])
      setLoading(false)
      return
    }

    const { data: referredProfiles, error: refErr } = await supabase
      .from("profiles")
      .select("id, username, avatar_url, created_at")
      .eq("referred_by", code)

    if (refErr) {
      console.error(refErr)
      setReferredUsers([])
    } else {
      setReferredUsers((referredProfiles as ReferredUser[]) ?? [])
    }

    setLoading(false)
  }, [router])

  useEffect(() => {
    void load()
  }, [load])

  useEffect(() => {
    if (typeof window !== "undefined") {
      setBaseUrl(window.location.origin)
    }
  }, [])

  const referralLink = referralCode ? `${baseUrl}?ref=${encodeURIComponent(referralCode)}` : ""
  const earnings = (totalReferrals || 0) * PLAN_PRICE * COMMISSION_RATE

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
    !pendingApp &&
    !referralCode &&
    (!latestApp || latestApp.status === "rejected")

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">
        <div className="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:p-10">
          <div className="mb-8 flex flex-wrap items-center justify-between gap-4">
            <h1 className="text-2xl font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent sm:text-3xl">
              Affiliate Dashboard
            </h1>
            <div className="flex items-center gap-2">
              {(showApplyCta || pendingApp) && (
                <button
                  type="button"
                  onClick={() => setShowAffiliateModal(true)}
                  className="rounded-lg bg-gradient-to-r from-emerald-500 to-blue-500 px-4 py-2 text-sm font-semibold text-white shadow-lg hover:opacity-95"
                >
                  {pendingApp ? "Update application" : "Apply to be an Affiliate"}
                </button>
              )}
              <button
                type="button"
                onClick={() => void load()}
                disabled={loading}
                className="rounded-lg bg-white/10 px-4 py-2 text-sm hover:bg-white/20 disabled:opacity-50"
              >
                {loading ? "Refreshing…" : "Refresh"}
              </button>
            </div>
          </div>

          {applicationStatusLabel === "pending" && (
            <div className="mb-6 rounded-xl border border-amber-500/40 bg-amber-500/10 px-4 py-3 text-sm text-amber-100">
              Your affiliate application is <strong>pending review</strong>. You can update your
              submission anytime before a decision is made.
            </div>
          )}

          {latestApp?.status === "rejected" && !pendingApp && (
            <div className="mb-6 rounded-xl border border-red-500/35 bg-red-500/10 px-4 py-3 text-sm text-red-100">
              Your previous application was <strong>not approved</strong>. You may submit a new
              application if you&apos;d like to apply again.
            </div>
          )}

          {referralCode && (
            <div className="mb-6 rounded-xl border border-emerald-500/40 bg-emerald-500/10 px-4 py-3 text-sm text-emerald-50">
              You&apos;re set up as an affiliate. Share your link below — your code is{" "}
              <span className="font-mono font-semibold text-white">{referralCode}</span>.
            </div>
          )}

          <div className="mb-8 grid grid-cols-1 gap-4 sm:grid-cols-3">
            <div className="rounded-xl border border-white/10 bg-white/5 p-5 backdrop-blur-md">
              <p className="text-sm text-gray-400">Total earnings</p>
              <p className="mt-1 text-2xl font-bold text-emerald-400">
                ${hasAffiliateAccess ? earnings.toFixed(2) : "0.00"}
              </p>
            </div>
            <div className="rounded-xl border border-white/10 bg-white/5 p-5 backdrop-blur-md">
              <p className="text-sm text-gray-400">Total referrals</p>
              <p className="mt-1 text-2xl font-bold text-white">
                {hasAffiliateAccess ? totalReferrals : 0}
              </p>
            </div>
            <div className="rounded-xl border border-white/10 bg-white/5 p-5 backdrop-blur-md">
              <p className="text-sm text-gray-400">Referral code</p>
              <p className="mt-1 break-all text-sm font-bold text-blue-300">
                {referralCode || "—"}
              </p>
            </div>
          </div>

          <div className="mb-8 rounded-xl border border-white/10 bg-white/5 p-6 backdrop-blur-md">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-blue-300">
              Share your link
            </h2>
            {!referralCode ? (
              <p className="mt-3 text-sm text-gray-400">
                {pendingApp
                  ? "Once approved, your referral code and link will appear here."
                  : "Apply for the affiliate program. When approved, your code and link will appear here."}
              </p>
            ) : (
              <>
                <p className="mt-1 text-xs text-gray-500">Your code</p>
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
                    className="shrink-0 rounded-lg bg-emerald-500 px-4 py-2 text-sm font-semibold hover:bg-emerald-600"
                  >
                    {copyDone ? "Copied!" : "Copy"}
                  </button>
                </div>
              </>
            )}
          </div>

          <div>
            <h2 className="mb-4 text-lg font-semibold text-blue-400">Referred users</h2>

            {loading ? (
              <p className="text-sm text-gray-400">Loading…</p>
            ) : !referralCode ? (
              <p className="rounded-xl border border-white/10 bg-white/5 p-6 text-center text-sm text-gray-400">
                No referrals yet — your list appears here once you have an active referral code.
              </p>
            ) : referredUsers.length === 0 ? (
              <p className="rounded-xl border border-white/10 bg-white/5 p-6 text-center text-sm text-gray-400">
                You have no referrals yet.
              </p>
            ) : (
              referredUsers.map((u) => (
                <div
                  key={u.id}
                  className="mb-3 flex items-center gap-3 rounded-xl bg-white/5 p-4 last:mb-0"
                >
                  <img
                    src={u.avatar_url || "/default-avatar.png"}
                    className="h-8 w-8 rounded-full"
                    alt=""
                  />
                  <span>{u.username?.trim() || "User"}</span>
                </div>
              ))
            )}
          </div>
        </div>
      </div>

      <AffiliateApplyModal
        open={showAffiliateModal}
        onClose={() => setShowAffiliateModal(false)}
        onSubmit={() => afterModalSubmit()}
        defaultFullName={displayName}
        defaultEmail={email}
      />
    </>
  )
}
