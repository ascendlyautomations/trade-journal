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

    // 🔥 GET AFFILIATE CODE (REAL SOURCE)
    const { data: affiliate } = await supabase
      .from("affiliates")
      .select("*")
      .eq("user_id", user.id)
      .single()

    if (affiliate) {
      setAffiliateCode(affiliate.code)
    }

    // 🔥 GET REFERRALS
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

      <div className="min-h-screen bg-[#0f172a] text-white p-6">

        <h1 className="text-2xl font-bold mb-6">💰 Affiliate Dashboard</h1>

        {/* STATS */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">

          <div className="bg-[#1e293b] p-6 rounded">
            <p className="text-gray-400">Affiliate Earnings (18%)</p>

            <h2 className="text-2xl font-bold text-emerald-400">
              ${earnings.toFixed(2)}
            </h2>

            <p className="text-gray-400 text-xs mt-1">
              From ${totalRevenue.toFixed(2)} total
            </p>
          </div>

          <div className="bg-[#1e293b] p-6 rounded">
            <p className="text-gray-400">Total Referrals</p>

            <h2 className="text-2xl font-bold">
              {profile.referral_count || 0}
            </h2>
          </div>

          <div className="bg-[#1e293b] p-6 rounded">
            <p className="text-gray-400">Your Code</p>

            <h2 className="text-2xl font-bold text-blue-400">
              {affiliateCode || "No Code"}
            </h2>
          </div>

        </div>

        {/* REFERRAL LINK */}
        {affiliateCode && (
          <div className="bg-[#1e293b] p-6 rounded mb-8">

            <p className="text-gray-400 mb-2">Your Referral Link</p>

            <div className="flex gap-2">

              <input
                value={referralLink}
                readOnly
                className="flex-1 bg-black px-3 py-2 rounded text-sm"
              />

              <button
                onClick={() => copyLink(referralLink)}
                className="bg-emerald-500 px-4 py-2 rounded"
              >
                Copy
              </button>

            </div>
          </div>
        )}

        {/* TABLE */}
        <div className="bg-[#1e293b] p-6 rounded">

          <h2 className="text-lg font-semibold mb-4">Your Referrals</h2>

          {loadingData ? (
            <p>Loading...</p>
          ) : referrals.length === 0 ? (
            <p className="text-gray-400">No referrals yet</p>
          ) : (
            <table className="w-full text-sm">
              <tbody>
                {referrals.map((ref, i) => (
                  <tr key={i} className="border-b border-white/10">
                    <td className="py-2">{ref.referred_user_id}</td>
                    <td className="py-2 text-emerald-400">
                      ${(ref.revenue * 0.18).toFixed(2)}
                    </td>
                    <td className="py-2">
                      {new Date(ref.created_at).toLocaleDateString()}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}

        </div>

      </div>
    </>
  )
}