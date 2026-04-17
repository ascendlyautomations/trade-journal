"use client"

import { useRouter } from "next/navigation"
import { useEffect } from "react"
import Navbar from "../components/Navbar"
import { supabase } from "../../lib/supabaseClient"
import { useUserProfile } from "../../lib/useUserProfile"

export default function BannedPage() {
  const router = useRouter()
  const { user, profile, loading } = useUserProfile()

  useEffect(() => {
    if (loading) return
    if (!user) {
      router.replace("/login")
    }
  }, [loading, user, router])

  if (loading || !user) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-8 text-white">
        Loading…
      </div>
    )
  }

  const reason = profile?.banned_reason ? String(profile.banned_reason) : null

  return (
    <>
      <Navbar />
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 py-12 text-white">
        <div className="mx-auto max-w-lg rounded-2xl border border-red-500/30 bg-red-950/40 p-8 text-center shadow-2xl backdrop-blur-xl">
          <h1 className="text-2xl font-semibold text-red-200">Account restricted</h1>
          <p className="mt-3 text-sm text-gray-200">
            This TradeTrax account has been suspended. If you believe this is a mistake, contact support.
          </p>
          {reason ? (
            <p className="mt-4 rounded-lg border border-white/10 bg-black/30 p-3 text-left text-sm text-gray-300">
              <span className="font-medium text-gray-100">Reason: </span>
              {reason}
            </p>
          ) : null}
          <button
            type="button"
            className="mt-8 w-full rounded-xl bg-white/10 py-3 text-sm font-semibold hover:bg-white/20"
            onClick={async () => {
              await supabase.auth.signOut()
              router.push("/login")
            }}
          >
            Sign out
          </button>
        </div>
      </div>
    </>
  )
}
