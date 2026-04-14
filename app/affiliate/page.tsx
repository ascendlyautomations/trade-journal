"use client"

import { useCallback, useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { supabase } from "../../lib/supabaseClient"
import Navbar from "../components/Navbar"

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
  const [currentUserId, setCurrentUserId] = useState<string | null>(null)
  const [referralCode, setReferralCode] = useState<string | null>(null)
  const [totalReferrals, setTotalReferrals] = useState(0)
  const [referredUsers, setReferredUsers] = useState<ReferredUser[]>([])
  const [copyDone, setCopyDone] = useState(false)
  const [showAffiliateModal, setShowAffiliateModal] = useState(false)
  const [experience, setExperience] = useState("")
  const [socialHandle, setSocialHandle] = useState("")
  const [why, setWhy] = useState("")
  const [baseUrl, setBaseUrl] = useState(
    process.env.NEXT_PUBLIC_BASE_URL || "http://localhost:3000"
  )

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
    setCurrentUserId(user.id)

    const { data: profile, error: profErr } = await supabase
      .from("profiles")
      .select("id, referral_code, referral_count")
      .eq("id", user.id)
      .single()

    if (profErr || !profile) {
      console.error(profErr)
      setReferralCode(null)
      setTotalReferrals(0)
      setReferredUsers([])
      setLoading(false)
      return
    }

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

  const referralLink = referralCode
    ? `${baseUrl}?ref=${encodeURIComponent(referralCode)}`
    : ""
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

  async function submitApplication() {
    if (!currentUserId) return

    const { error } = await supabase.from("affiliate_applications").insert({
      user_id: currentUserId,
      experience,
      social_handle: socialHandle,
      why,
    })

    if (error) {
      console.error("affiliate application insert:", error)
      return
    }

    setShowAffiliateModal(false)
    setExperience("")
    setSocialHandle("")
    setWhy("")
  }

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
              <button
                type="button"
                onClick={() => setShowAffiliateModal(true)}
                className="bg-green-500 px-4 py-2 rounded text-white"
              >
                Apply to be an Affiliate
              </button>
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

          <div className="mb-8 grid grid-cols-1 gap-4 sm:grid-cols-3">
            <div className="rounded-xl border border-white/10 bg-white/5 p-5 backdrop-blur-md">
              <p className="text-sm text-gray-400">Total earnings</p>
              <p className="mt-1 text-2xl font-bold text-emerald-400">
                ${earnings.toFixed(2)}
              </p>
            </div>
            <div className="rounded-xl border border-white/10 bg-white/5 p-5 backdrop-blur-md">
              <p className="text-sm text-gray-400">Total referrals</p>
              <p className="mt-1 text-2xl font-bold text-white">{totalReferrals}</p>
            </div>
            <div className="rounded-xl border border-white/10 bg-white/5 p-5 backdrop-blur-md">
              <p className="text-sm text-gray-400">Referral code</p>
              <p className="mt-1 text-sm font-bold text-blue-300 break-all">
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
                No referral code on your profile yet
              </p>
            ) : (
              <>
                <p className="mt-1 text-xs text-gray-500">Your code</p>
                <p className="mt-0.5 font-mono text-lg font-semibold text-white">
                  {referralCode}
                </p>
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
            ) : referredUsers.length === 0 ? (
              <p className="rounded-xl border border-white/10 bg-white/5 p-6 text-center text-sm text-gray-400">
                You have no referrals yet.
              </p>
            ) : (
              referredUsers.map((user) => (
                <div
                  key={user.id}
                  className="mb-3 flex items-center gap-3 rounded-xl bg-white/5 p-4 last:mb-0"
                >
                  <img
                    src={user.avatar_url || "/default-avatar.png"}
                    className="w-8 h-8 rounded-full"
                    alt=""
                  />
                  <span>{user.username?.trim() || "User"}</span>
                </div>
              ))
            )}
          </div>
        </div>
      </div>

      {showAffiliateModal && (
        <div className="fixed inset-0 bg-black/40 backdrop-blur-sm flex items-center justify-center z-50">
          <div className="bg-[#1e2a4a] p-6 rounded-xl w-[400px]">
            <h2 className="text-white text-lg mb-4">Affiliate Application</h2>

            <textarea
              placeholder="Your experience trading or promoting..."
              value={experience}
              onChange={(e) => setExperience(e.target.value)}
              className="mb-3 w-full rounded border border-white/10 bg-[#0f172a] p-2 text-sm text-white placeholder:text-gray-400"
            />
            <input
              placeholder="Social handle (optional)"
              value={socialHandle}
              onChange={(e) => setSocialHandle(e.target.value)}
              className="mb-3 w-full rounded border border-white/10 bg-[#0f172a] p-2 text-sm text-white placeholder:text-gray-400"
            />
            <textarea
              placeholder="Why should we accept you?"
              value={why}
              onChange={(e) => setWhy(e.target.value)}
              className="w-full rounded border border-white/10 bg-[#0f172a] p-2 text-sm text-white placeholder:text-gray-400"
            />

            <div className="flex justify-end gap-2 mt-4">
              <button
                type="button"
                onClick={() => setShowAffiliateModal(false)}
                className="rounded bg-white/10 px-3 py-1.5 text-sm text-white hover:bg-white/20"
              >
                Cancel
              </button>

              <button
                type="button"
                onClick={() => void submitApplication()}
                className="rounded bg-blue-500 px-4 py-2 text-sm font-medium text-white hover:bg-blue-600"
              >
                Submit
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}
