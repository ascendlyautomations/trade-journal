"use client"

import { useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import { useUserProfile } from "../../lib/useUserProfile"
import Navbar from "../components/Navbar"

export default function AffiliateDashboard() {
  const { user, profile, loading } = useUserProfile()

  const [referrals, setReferrals] = useState<any[]>([])
  const [affiliateCode, setAffiliateCode] = useState<string | null>(null)
  const [loadingData, setLoadingData] = useState(true)

  const BASE_URL =
    process.env.NEXT_PUBLIC_BASE_URL || "http://localhost:3000"

  useEffect(() => {
    if (user) fetchData()
  }, [user])

  async function fetchData() {
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

    setReferrals(refs || [])
    setLoadingData(false)
  }

  function copyLink(link: string) {
    navigator.clipboard.writeText(link)
    alert("Copied 🚀")
  }

  if (loading || !profile) return null

  const totalRevenue = Number(profile.referral_revenue || 0)
  const earnings = totalRevenue * 0.18

  const referralLink = affiliateCode
    ? `${BASE_URL}?ref=${affiliateCode}`
    : ""

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">

        <div className="max-w-6xl mx-auto p-10">

          {/* HEADER */}
          <h1 className="text-3xl font-bold mb-8 bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
            Affiliate Dashboard
          </h1>

          {/* STATS */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">

            <div className="bg-white/5 backdrop-blur-md border border-white/10 p-6 rounded-xl">
              <p className="text-gray-400 text-sm">Affiliate Earnings</p>

              <h2 className="text-3xl font-bold text-emerald-400 mt-1">
                ${earnings.toFixed(2)}
              </h2>

              <p className="text-gray-400 text-xs mt-2">
                From ${totalRevenue.toFixed(2)} total revenue
              </p>
            </div>

            <div className="bg-white/5 backdrop-blur-md border border-white/10 p-6 rounded-xl">
              <p className="text-gray-400 text-sm">Total Referrals</p>

              <h2 className="text-3xl font-bold mt-1">
                {profile.referral_count || 0}
              </h2>
            </div>

            <div className="bg-white/5 backdrop-blur-md border border-white/10 p-6 rounded-xl">
              <p className="text-gray-400 text-sm">Your Code</p>

              <h2 className="text-2xl font-bold text-blue-400 mt-1">
                {affiliateCode || "No Code"}
              </h2>
            </div>

          </div>

          {/* REFERRAL LINK */}
          {affiliateCode && (
            <div className="bg-white/5 backdrop-blur-md border border-white/10 p-6 rounded-xl mb-8">

              <p className="text-gray-400 mb-3">Your Referral Link</p>

              <div className="flex gap-2">

                <input
                  value={referralLink}
                  readOnly
                  className="flex-1 bg-[#0f172a] border border-white/10 px-3 py-2 rounded text-sm text-white"
                />

                <button
                  onClick={() => copyLink(referralLink)}
                  className="bg-emerald-500 hover:bg-emerald-600 px-4 py-2 rounded font-semibold transition"
                >
                  Copy
                </button>

              </div>
            </div>
          )}

          {/* REFERRALS TABLE */}
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
                          ${(ref.revenue * 0.18).toFixed(2)}
                        </td>

                        <td className="py-3 text-gray-400">
                          {new Date(ref.created_at).toLocaleDateString()}
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