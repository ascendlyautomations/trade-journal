"use client"

import { useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import Navbar from "../components/Navbar"

type ReferralRow = {
  referred_user_id?: string
  revenue?: number
  created_at?: string
}

/** Full `profiles` row from Supabase; these keys are what the dashboard displays. */
type ProfileRow = Record<string, unknown> & {
  referral_count?: number | null
  referral_earnings?: number | null
  referral_code?: string | null
}

export default function AffiliateDashboard() {
  const [profile, setProfile] = useState<ProfileRow | null>(null)

  const [referrals, setReferrals] = useState<ReferralRow[]>([])
  const [affiliateCode, setAffiliateCode] = useState<string | null>(null)
  const [loadingData, setLoadingData] = useState(true)

  const BASE_URL =
    process.env.NEXT_PUBLIC_BASE_URL || "http://localhost:3000"

  async function fetchProfile() {
  const { data: authData } = await supabase.auth.getUser()

  console.log("AUTH DATA:", authData)

  if (!authData?.user) {
    console.log("❌ NO USER")
    return
  }

  const userId = authData.user.id

  const { data, error } = await supabase
    .from("profiles")
    .select("referral_count, referral_earnings, referral_code")
    .eq("id", userId)
    .single() // 🚨 THIS IS THE FIX

  console.log("PROFILE RESULT:", data, error)

  if (error) {
    console.log("❌ FETCH ERROR:", error)
    return
  }

  if (data) {
    setProfile(data)
  }
}

  async function fetchReferralsAndAffiliate() {
    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (!user) {
      setLoadingData(false)
      return
    }

    setLoadingData(true)

    const { data: affiliate } = await supabase
      .from("affiliates")
      .select("*")
      .eq("user_id", user.id)
      .single()

    if (affiliate) {
      setAffiliateCode(affiliate.code)
    }

    const { data: refs } = await supabase
      .from("referrals")
      .select("*")
      .eq("affiliate_id", affiliate?.id)
      .order("created_at", { ascending: false })

    setReferrals((refs as ReferralRow[]) || [])
    setLoadingData(false)
  }

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- mount-only profile load
    fetchProfile()
  }, [])

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- mount-only referrals table
    void fetchReferralsAndAffiliate()
  }, [])

  function copyLink(link: string) {
    navigator.clipboard.writeText(link)
    alert("Copied 🚀")
  }

  const linkCode =
    (profile?.referral_code != null &&
    String(profile.referral_code).trim() !== ""
      ? String(profile.referral_code)
      : null) ||
    affiliateCode ||
    ""

  const referralLink = linkCode ? `${BASE_URL}?ref=${linkCode}` : ""

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">

        <div className="max-w-6xl mx-auto p-10">

          <div className="flex flex-wrap items-center justify-between gap-4 mb-8">
            <h1 className="text-3xl font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
              Affiliate Dashboard
            </h1>
            <button
              type="button"
              onClick={fetchProfile}
              className="px-4 py-2 bg-white/10 rounded-lg hover:bg-white/20"
            >
              Refresh Data
            </button>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">

            <div className="bg-white/5 backdrop-blur-md border border-white/10 p-6 rounded-xl">
              <p className="text-gray-400 text-sm">Affiliate Earnings</p>

              <h2 className="text-3xl font-bold text-emerald-400 mt-1">
                ${Number(profile?.referral_earnings || 0).toFixed(2)}
              </h2>
            </div>

            <div className="bg-white/5 backdrop-blur-md border border-white/10 p-6 rounded-xl">
              <p className="text-gray-400 text-sm">Total Referrals</p>

              <h2 className="text-3xl font-bold mt-1">
                {profile?.referral_count || 0}
              </h2>
            </div>

            <div className="bg-white/5 backdrop-blur-md border border-white/10 p-6 rounded-xl">
              <p className="text-gray-400 text-sm">Your Code</p>

              <h2 className="text-2xl font-bold text-blue-400 mt-1">
                {profile?.referral_code || "—"}
              </h2>
            </div>

          </div>

          {linkCode && (
            <div className="bg-white/5 backdrop-blur-md border border-white/10 p-6 rounded-xl mb-8">

              <p className="text-gray-400 mb-3">Your Referral Link</p>

              <div className="flex gap-2">

                <input
                  value={referralLink}
                  readOnly
                  className="flex-1 bg-[#0f172a] border border-white/10 px-3 py-2 rounded text-sm text-white"
                />

                <button
                  type="button"
                  onClick={() => copyLink(referralLink)}
                  className="bg-emerald-500 hover:bg-emerald-600 px-4 py-2 rounded font-semibold transition"
                >
                  Copy
                </button>

              </div>
            </div>
          )}

          <div className="bg-white/5 backdrop-blur-md border border-white/10 p-6 rounded-xl">

            <h2 className="text-lg font-semibold mb-4 text-blue-400">
              Your Referrals
            </h2>

            {loadingData ? (
              <p className="text-gray-400">Loading...</p>
            ) : referrals.length === 0 ? (
              <p className="text-gray-400">No referrals yet</p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">

                  <thead>
                    <tr className="text-gray-400 text-left border-b border-white/10">
                      <th className="py-2">User</th>
                      <th className="py-2">Earnings</th>
                      <th className="py-2">Date</th>
                    </tr>
                  </thead>

                  <tbody>
                    {referrals.map((ref, i) => (
                      <tr
                        key={i}
                        className="border-b border-white/10 hover:bg-white/5 transition"
                      >
                        <td className="py-3 truncate max-w-[150px]">
                          {ref.referred_user_id}
                        </td>

                        <td className="py-3 text-emerald-400 font-semibold">
                          ${((ref.revenue ?? 0) * 0.18).toFixed(2)}
                        </td>

                        <td className="py-3 text-gray-400">
                          {ref.created_at
                            ? new Date(ref.created_at).toLocaleDateString()
                            : ""}
                        </td>
                      </tr>
                    ))}
                  </tbody>

                </table>
              </div>
            )}

          </div>

        </div>

      </div>
    </>
  )
}
