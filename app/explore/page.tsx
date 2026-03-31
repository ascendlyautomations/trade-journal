"use client"

import Navbar from "../components/Navbar"
import { useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import { useRouter } from "next/navigation"

export default function ExplorePage() {
  const [users, setUsers] = useState<any[]>([])
  const [topUsers, setTopUsers] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  const router = useRouter()

  useEffect(() => {
    init()
  }, [])

  async function init() {
    await fetchRandomUsers()
    await fetchTopUsers()
    setLoading(false)
  }

  // 🔥 RANDOM USERS
  async function fetchRandomUsers() {
    const { data } = await supabase
      .from("profiles")
      .select("id, username")
      .limit(20)

    // shuffle users
    const shuffled = (data || []).sort(() => 0.5 - Math.random())

    setUsers(shuffled)
  }

  // 🔥 TOP USERS BY PNL
  async function fetchTopUsers() {
    const { data } = await supabase
      .from("trades")
      .select("user_id, pnl")

    if (!data) return

    const pnlMap: any = {}

    data.forEach((t) => {
      pnlMap[t.user_id] = (pnlMap[t.user_id] || 0) + (t.pnl || 0)
    })

    const sorted = Object.entries(pnlMap)
      .sort((a: any, b: any) => b[1] - a[1])
      .slice(0, 5)

    const usersData = await Promise.all(
      sorted.map(async ([userId, pnl]) => {
        const { data } = await supabase
          .from("profiles")
          .select("id, username")
          .eq("id", userId)
          .single()

        return {
          id: data?.id,
          username: data?.username,
          pnl
        }
      })
    )

    setTopUsers(usersData)
  }

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white p-6">

        <div className="max-w-5xl mx-auto">

          <h1 className="text-2xl font-semibold mb-6">
            Explore
          </h1>

          {loading ? (
            <p className="text-gray-400">Loading...</p>
          ) : (
            <>
              {/* 🔥 TOP TRADERS */}
              <div className="mb-10">

                <h2 className="text-lg mb-4 text-emerald-400">
                  Top Traders
                </h2>

                <div className="grid grid-cols-1 md:grid-cols-3 gap-4">

                  {topUsers.map((u, i) => (
                    <div
                      key={i}
                      onClick={() => router.push(`/profile/${u.id}`)}
                      className="bg-white/5 border border-white/10 p-4 rounded-xl cursor-pointer hover:bg-white/10"
                    >
                      <p className="font-semibold">@{u.username}</p>
                      <p className={`text-sm ${u.pnl >= 0 ? "text-green-400" : "text-red-400"}`}>
                        ${u.pnl.toLocaleString()}
                      </p>
                    </div>
                  ))}

                </div>

              </div>

              {/* 🔥 DISCOVER USERS */}
              <div>

                <h2 className="text-lg mb-4 text-blue-400">
                  Discover Users
                </h2>

                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">

                  {users.map((u) => (
                    <div
                      key={u.id}
                      onClick={() => router.push(`/profile/${u.id}`)}
                      className="bg-white/5 border border-white/10 p-4 rounded-xl cursor-pointer hover:bg-white/10 flex items-center justify-center"
                    >
                      @{u.username}
                    </div>
                  ))}

                </div>

              </div>
            </>
          )}

        </div>

      </div>
    </>
  )
}