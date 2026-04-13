"use client"

import { useCallback, useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { supabase } from "../../lib/supabaseClient"
import Navbar from "../components/Navbar"

type MeProfile = {
  id: string
  referral_code?: string | null
}

type ReferredUser = {
  id: string
  username?: string | null
  subscription_status?: string | null
  created_at?: string | null
}

export default function AffiliateDashboard() {
  const router = useRouter()
  const [loading, setLoading] = useState(true)
  const [profile, setProfile] = useState<MeProfile | null>(null)
  const [referrals, setReferrals] = useState<ReferredUser[]>([])
  const [earningsByUserId, setEarningsByUserId] = useState<Record<string, number>>({})
  const [ledgerTotal, setLedgerTotal] = useState(0)
  const [copyDone, setCopyDone] = useState(false)

  const baseUrl =
    typeof window !== "undefined"
      ? window.location.origin
      : process.env.NEXT_PUBLIC_BASE_URL || "http://localhost:3000"

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

    const { data: prof, error: profErr } = await supabase
      .from("profiles")
      .select("id, referral_code")
      .eq("id", user.id)
      .single()

    if (profErr || !prof) {
      console.error(profErr)
      setProfile(null)
      setReferrals([])
      setEarningsByUserId({})
      setLedgerTotal(0)
      setLoading(false)
      return
    }

    setProfile(prof as MeProfile)

    const { data: ledger, error: ledgerErr } = await supabase
      .from("referrals")
      .select("*")
      .eq("referrer_user_id", user.id)

    if (ledgerErr) {
      console.error("referrals ledger:", ledgerErr)
      setEarningsByUserId({})
      setLedgerTotal(0)
      setReferrals([])
      setLoading(false)
      return
    }

    const earningsMap: Record<string, number> = {}
    let total = 0

    for (const entry of ledger ?? []) {
      const raw = entry.amount_earned
      const amt =
        raw != null && raw !== "" ? Number(raw) : 0
      const add = Number.isFinite(amt) ? amt : 0
      const refId = entry.referred_user_id
      if (refId == null || refId === "") continue
      const id = String(refId)
      if (!earningsMap[id]) earningsMap[id] = 0
      earningsMap[id] += add
      total += add
    }

    setEarningsByUserId(earningsMap)
    setLedgerTotal(total)

    const code =
      prof.referral_code != null ? String(prof.referral_code).trim() : ""

    if (!code) {
      setReferrals([])
      setLoading(false)
      return
    }

    const { data: referredProfiles, error: refErr } = await supabase
      .from("profiles")
      .select("*")
      .eq("referred_by", code)

    if (refErr) {
      console.error(refErr)
      setReferrals([])
    } else {
      setReferrals((referredProfiles as ReferredUser[]) ?? [])
    }

    setLoading(false)
  }, [router])

  useEffect(() => {
    void load()
  }, [load])

  const linkCode =
    profile?.referral_code != null ? String(profile.referral_code).trim() : ""

  const referralLink = linkCode ? `${baseUrl}?ref=${encodeURIComponent(linkCode)}` : ""

  const totalReferrals = referrals.length
  const activeReferrals = referrals.filter(
    (r) => String(r.subscription_status ?? "").toLowerCase() === "active"
  ).length

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

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">
        <div className="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:p-10">
          <div className="mb-8 flex flex-wrap items-center justify-between gap-4">
            <h1 className="text-2xl font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent sm:text-3xl">
              Affiliate Dashboard
            </h1>
            <button
              type="button"
              onClick={() => void load()}
              disabled={loading}
              className="rounded-lg bg-white/10 px-4 py-2 text-sm hover:bg-white/20 disabled:opacity-50"
            >
              {loading ? "Refreshing…" : "Refresh"}
            </button>
          </div>

          <div className="mb-8 grid grid-cols-1 gap-4 sm:grid-cols-3">
            <div className="rounded-xl border border-white/10 bg-white/5 p-5 backdrop-blur-md">
              <p className="text-sm text-gray-400">Total earnings</p>
              <p className="mt-1 text-2xl font-bold text-emerald-400">
                ${ledgerTotal.toFixed(2)}
              </p>
            </div>
            <div className="rounded-xl border border-white/10 bg-white/5 p-5 backdrop-blur-md">
              <p className="text-sm text-gray-400">Total referrals</p>
              <p className="mt-1 text-2xl font-bold text-white">{totalReferrals}</p>
            </div>
            <div className="rounded-xl border border-white/10 bg-white/5 p-5 backdrop-blur-md">
              <p className="text-sm text-gray-400">Active referrals</p>
              <p className="mt-1 text-2xl font-bold text-blue-300">{activeReferrals}</p>
            </div>
          </div>

          <div className="mb-8 rounded-xl border border-white/10 bg-white/5 p-6 backdrop-blur-md">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-blue-300">
              Share your link
            </h2>
            {!linkCode ? (
              <p className="mt-3 text-sm text-gray-400">
                No referral code on your profile yet. Contact support or check your account
                setup.
              </p>
            ) : (
              <>
                <p className="mt-1 text-xs text-gray-500">Your code</p>
                <p className="mt-0.5 font-mono text-lg font-semibold text-white">{linkCode}</p>
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
            ) : referrals.length === 0 ? (
              <p className="rounded-xl border border-white/10 bg-white/5 p-6 text-center text-sm text-gray-400">
                You have no referrals yet. Share your link to start earning.
              </p>
            ) : (
              referrals.map((user) => (
                <div
                  key={user.id}
                  className="mb-3 flex items-center justify-between rounded-xl bg-white/5 p-4 last:mb-0"
                >
                  <div>
                    <p className="font-semibold">{user.username?.trim() || "User"}</p>

                    <p className="text-sm text-gray-400">
                      Joined:{" "}
                      {user.created_at
                        ? new Date(user.created_at).toLocaleDateString()
                        : "—"}
                    </p>

                    <p className="text-sm">
                      Status: {user.subscription_status || "inactive"}
                    </p>
                  </div>

                  <div className="rounded-lg bg-black/30 px-4 py-2 text-right">
                    <p className="text-xs text-gray-400">Earned</p>
                    <p className="text-lg font-bold text-green-400">
                      ${earningsByUserId[user.id]?.toFixed(2) || "0.00"}
                    </p>
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </>
  )
}
