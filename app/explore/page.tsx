"use client"

import Navbar from "../components/Navbar"
import { useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import { useRouter } from "next/navigation"
import { formatPnlCurrency } from "@/lib/formatMoney"
import { pnlTextClassName } from "@/lib/formatDisplay"

export default function ExplorePage() {
  const [users, setUsers] = useState<any[]>([])
  const [topUsers, setTopUsers] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState("")
  const [results, setResults] = useState<any[]>([])
  const [loadingSearch, setLoadingSearch] = useState(false)

  const router = useRouter()

  useEffect(() => {
    init()
  }, [])

  useEffect(() => {
    if (!search) {
      setResults([])
      return
    }

    const delayDebounce = setTimeout(async () => {
      setLoadingSearch(true)

      const { data } = await supabase
        .from("profiles")
        .select("id, username, name, avatar_url")
        .or(`username.ilike.%${search}%,name.ilike.%${search}%`)
        .limit(6)

      setResults(data || [])
      setLoadingSearch(false)
    }, 300)

    return () => clearTimeout(delayDebounce)
  }, [search])

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

          <div className="relative mb-6">
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search users..."
              className="w-full p-3 rounded-xl bg-[#0f172a] text-white border border-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500"
            />

            {loadingSearch && (
              <p className="mt-2 text-sm text-gray-400">Searching...</p>
            )}

            {results.length > 0 && (
              <div className="absolute mt-2 w-full bg-[#1e293b] border border-gray-700 rounded-xl shadow-lg z-50">
                {results.map((user) => (
                  <div
                    key={user.id}
                    onClick={() => router.push(`/profile/${user.id}`)}
                    className="flex items-center gap-3 p-3 hover:bg-gray-700 cursor-pointer transition"
                  >
                    <img
                      src={user.avatar_url || "/default-avatar.png"}
                      alt=""
                      loading="lazy"
                      decoding="async"
                      className="w-8 h-8 rounded-full object-cover"
                    />
                    <div>
                      <p className="text-white font-medium">@{user.username}</p>
                      <p className="text-gray-400 text-sm">{user.name}</p>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

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
                      <p className={`text-sm ${pnlTextClassName(u.pnl, { variant: "green" })}`}>
                        {formatPnlCurrency(Number(u.pnl))}
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