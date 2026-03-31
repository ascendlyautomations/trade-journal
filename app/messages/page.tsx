"use client"

import Navbar from "../components/Navbar"
import { useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import { useRouter } from "next/navigation"

export default function MessagesPage() {
  const [conversations, setConversations] = useState<any[]>([])
  const [user, setUser] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState("")

  const router = useRouter()

  useEffect(() => {
    init()
  }, [])

  async function init() {
    const {
      data: { user }
    } = await supabase.auth.getUser()

    if (!user) {
      router.push("/login")
      return
    }

    setUser(user)

    await fetchConversations(user.id)
    setLoading(false)
  }

  async function fetchConversations(userId: string) {
    const { data: parts } = await supabase
      .from("conversation_participants")
      .select("conversation_id")
      .eq("user_id", userId)

    if (!parts || parts.length === 0) {
      setConversations([])
      return
    }

    const convoIds = parts.map((p) => p.conversation_id)

    const convoData = await Promise.all(
      convoIds.map(async (convoId) => {

        // 🔥 FIXED: include avatar_url
        const { data: users } = await supabase
          .from("conversation_participants")
          .select(`
            user_id,
            profiles (username, avatar_url)
          `)
          .eq("conversation_id", convoId)

        const otherUser = users?.find((u: any) => u.user_id !== userId)
        const rawProfile = otherUser?.profiles
        const profile = Array.isArray(rawProfile) ? rawProfile[0] : rawProfile

        const { data: messages } = await supabase
          .from("direct_messages")
          .select("content")
          .eq("conversation_id", convoId)
          .order("created_at", { ascending: false })
          .limit(1)

        // 🔥 FIXED: return avatar_url
        return {
          id: convoId,
          username: profile?.username || "user",
          avatar_url: profile?.avatar_url ?? null,
          lastMessage: messages?.[0]?.content || "No messages yet"
        }
      })
    )

    setConversations(convoData)
  }

  const filteredConversations = conversations.filter((c) =>
    c.username.toLowerCase().includes(search.toLowerCase())
  )

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white p-6">

        <div className="max-w-3xl mx-auto">

          <h1 className="text-2xl font-semibold mb-4">
            Messages
          </h1>

          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search conversations..."
            className="w-full mb-6 p-3 bg-black border border-white/10 rounded focus:outline-none focus:border-emerald-400"
          />

          {loading ? (
            <p className="text-gray-400">Loading...</p>
          ) : filteredConversations.length === 0 ? (
            <p className="text-gray-400">No conversations found</p>
          ) : (
            <div className="space-y-3">

              {filteredConversations.map((c) => (
                <div
                  key={c.id}
                  onClick={() => router.push(`/messages/${c.id}`)}
                  className="bg-white/5 border border-white/10 p-4 rounded-xl cursor-pointer hover:bg-white/10 transition"
                >
                  <div className="flex items-center gap-3">

                    {c.avatar_url ? (
                      <img
                        src={c.avatar_url}
                        className="w-10 h-10 rounded-full object-cover"
                      />
                    ) : (
                      <div className="w-10 h-10 rounded-full bg-gray-600" />
                    )}

                    <div>
                      <p className="text-emerald-400 font-semibold">
                        @{c.username}
                      </p>

                      <p className="text-sm text-gray-400 truncate">
                        {c.lastMessage}
                      </p>
                    </div>

                  </div>
                </div>
              ))}

            </div>
          )}

        </div>

      </div>
    </>
  )
}