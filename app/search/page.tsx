"use client"

import Navbar from "../components/Navbar"
import { useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import { useRouter } from "next/navigation"

export default function SearchPage() {
  const [search, setSearch] = useState("")
  const [users, setUsers] = useState<any[]>([])
  const [loading, setLoading] = useState(false)

  const router = useRouter()

  async function handleSearch(value: string) {
    setSearch(value)

    if (!value.trim()) {
      setUsers([])
      return
    }

    setLoading(true)

    const { data, error } = await supabase
      .from("profiles")
      .select("id, username")
      .ilike("username", `%${value}%`)
      .limit(10)

    if (error) {
      console.error("Supabase error (search profiles):", error)
    }

    if (!data) {
      console.log("No data returned from profile search")
    }

    setUsers(data || [])
    setLoading(false)
  }

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white p-6">

        <div className="max-w-2xl mx-auto">

          <h1 className="text-2xl font-semibold mb-4">
            Search Users
          </h1>

          <input
            value={search}
            onChange={(e) => handleSearch(e.target.value)}
            placeholder="Search usernames..."
            className="w-full p-3 mb-6 bg-black border border-white/10 rounded focus:outline-none focus:border-emerald-400"
          />

          {loading && <p className="text-gray-400">Searching...</p>}

          <div className="space-y-2">

            {users.map((u, i) => (
              <div
                key={i}
                onClick={() => {
                  console.log("Navigating to profile:", u.id)
                  router.push(`/profile/${u.id}`)
                }}
                className="p-3 bg-white/5 border border-white/10 rounded cursor-pointer hover:bg-white/10"
              >
                @{u.username}
              </div>
            ))}

          </div>

        </div>

      </div>
    </>
  )
}