"use client"

import Link from "next/link"
import { useEffect, useState } from "react"
import { supabase } from "@/lib/supabaseClient"

export default function PublicNavbar() {
  const [user, setUser] = useState<any>(null)

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => {
      setUser(data.user ?? null)
    })
  }, [])

  useEffect(() => {
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_, session) => {
      setUser(session?.user || null)
    })

    return () => subscription.unsubscribe()
  }, [])

  return (
    <div className="w-full flex justify-between items-center px-6 h-[64px] bg-[#0f172a] text-white border-b border-gray-700">
      <div className="flex items-center gap-6 whitespace-nowrap">
        <Link
          href="/"
          className="text-lg font-bold whitespace-nowrap bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent"
        >
          TradeTraxs
        </Link>

        <Link
          href="/faq"
          className="text-sm font-medium whitespace-nowrap hover:text-blue-400 transition"
        >
          FAQ
        </Link>

        <Link
          href="/pricing"
          className="text-sm font-medium whitespace-nowrap hover:text-blue-400 transition"
        >
          Pricing
        </Link>
      </div>

      <div className="flex items-center gap-4 whitespace-nowrap">
        {!user && (
          <Link
            href="/login"
            className="text-sm font-medium whitespace-nowrap bg-blue-500 px-4 py-1 rounded"
          >
            Login
          </Link>
        )}

        {user && (
          <>
            <Link
              href="/dashboard"
              className="text-sm font-medium whitespace-nowrap bg-green-500 px-4 py-1 rounded"
            >
              Dashboard
            </Link>

            <Link
              href={`/profile/${user.id}`}
              className="text-sm font-medium whitespace-nowrap border px-3 py-1 rounded"
            >
              Profile
            </Link>
          </>
        )}
      </div>
    </div>
  )
}
