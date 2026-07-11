"use client"

import { Card, EmptyState } from "@/app/components/ui"
import { useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import { useRouter } from "next/navigation"
import { profilePath } from "@/lib/profileRoutes"
import { devLog } from "@/lib/devLog"

export default function SearchPage() {
  const [search, setSearch] = useState("")
  const [users, setUsers] = useState<any[]>([])
  const [loading, setLoading] = useState(false)
  const [searchError, setSearchError] = useState<string | null>(null)

  const router = useRouter()

  async function handleSearch(value: string) {
    setSearch(value)

    if (!value.trim()) {
      setUsers([])
      setSearchError(null)
      return
    }

    setLoading(true)
    setSearchError(null)

    const { data, error } = await supabase
      .from("profiles")
      .select("id, username")
      .ilike("username", `%${value}%`)
      .neq("is_private", true)
      .limit(10)

    if (error) {
      console.error("Supabase error (search profiles):", error)
      setUsers([])
      setSearchError("Couldn't search users. Please try again.")
      setLoading(false)
      return
    }

    if (!data) {
      devLog("No data returned from profile search")
    }

    setUsers(data || [])
    setLoading(false)
  }

  return (
    <>

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white p-6">

        <div className="max-w-2xl mx-auto">

          <h1 className="mb-4 text-2xl font-semibold text-blue-300">
            Search Users
          </h1>

          <input
            value={search}
            onChange={(e) => handleSearch(e.target.value)}
            placeholder="Search usernames..."
            className="w-full p-3 mb-6 bg-black border border-white/10 rounded focus:outline-none focus:border-emerald-400"
          />

          {loading ? <p className="text-gray-400">Searching...</p> : null}

          {!loading && search.trim() && users.length === 0 ? (
            <EmptyState
              title={searchError ? "Couldn't Search Users" : "No users found"}
              description={searchError ?? "Try a different username."}
              action={
                searchError ? (
                  <button
                    type="button"
                    onClick={() => void handleSearch(search)}
                    className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600"
                  >
                    Retry
                  </button>
                ) : undefined
              }
            />
          ) : null}

          {!loading && !search.trim() ? (
            <EmptyState
              title="Search traders"
              description="Enter a username to find profiles."
              className="py-8"
            />
          ) : null}

          {users.length > 0 ? (
            <div className="space-y-2">
              {users.map((u) => (
                <Card
                  key={u.id}
                  padding="sm"
                  interactive
                  onClick={() => {
                    router.push(profilePath(u))
                  }}
                >
                  @{u.username}
                </Card>
              ))}
            </div>
          ) : null}

        </div>

      </div>
    </>
  )
}