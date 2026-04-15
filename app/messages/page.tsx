"use client"

import Navbar from "../components/Navbar"
import { useCallback, useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import { useRouter } from "next/navigation"

function sortConversationsDesc(list: any[]) {
  return [...list].sort(
    (a, b) => {
      const aPinned = a?.is_pinned === true
      const bPinned = b?.is_pinned === true
      if (aPinned !== bPinned) return aPinned ? -1 : 1
      return (
        new Date(b.last_message_at || 0).getTime() -
        new Date(a.last_message_at || 0).getTime()
      )
    }
  )
}

export default function MessagesPage() {
  const [conversations, setConversations] = useState<any[]>([])
  const [user, setUser] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState("")
  const [showGroupModal, setShowGroupModal] = useState(false)
  const [showDMModal, setShowDMModal] = useState(false)
  const [allUsers, setAllUsers] = useState<any[]>([])
  const [groupSearchQuery, setGroupSearchQuery] = useState("")
  const [dmSearchQuery, setDmSearchQuery] = useState("")
  const [groupResults, setGroupResults] = useState<any[]>([])
  const [dmResults, setDmResults] = useState<any[]>([])
  const [groupSelectedUsers, setGroupSelectedUsers] = useState<any[]>([])
  const [dmSelectedUsers, setDmSelectedUsers] = useState<any[]>([])
  const [groupName, setGroupName] = useState("")
  const [creatingGroup, setCreatingGroup] = useState(false)
  const [creatingDM, setCreatingDM] = useState(false)
  const [openConvoMenuId, setOpenConvoMenuId] = useState<string | null>(null)

  const router = useRouter()

  function mergeNewConversation(prev: any[], newConversation: any) {
    if (prev.some((c) => c.id === newConversation.id)) return prev
    const updated = [newConversation, ...prev]
    return sortConversationsDesc(updated)
  }

  function openDMModal() {
    setDmSelectedUsers([])
    setDmSearchQuery("")
    setDmResults([])
    setShowDMModal(true)
  }

  useEffect(() => {
    if (!showGroupModal || !user?.id) return
    const query = groupSearchQuery.trim()
    if (!query) {
      setGroupResults([])
      return
    }

    const fetchUsers = async () => {
      const { data } = await supabase
        .from("profiles")
        .select("id, username, name, avatar_url")
        .neq("id", user.id)
        .or(`username.ilike.%${query}%,name.ilike.%${query}%`)
        .limit(10)

      setGroupResults(data || [])
    }

    void fetchUsers()
  }, [groupSearchQuery, showGroupModal, user?.id])

  useEffect(() => {
    if (!showDMModal || !user?.id) return
    const query = dmSearchQuery.trim()
    if (!query) {
      setDmResults([])
      return
    }

    const fetchUsers = async () => {
      const { data } = await supabase
        .from("profiles")
        .select("id, username, name, avatar_url")
        .neq("id", user.id)
        .or(`username.ilike.%${query}%,name.ilike.%${query}%`)
        .limit(10)

      setDmResults(data || [])
    }

    void fetchUsers()
  }, [dmSearchQuery, showDMModal, user?.id])

  useEffect(() => {
    init()
  }, [])

  useEffect(() => {
    const handler = (e: Event) => {
      const ce = e as CustomEvent<{
        conversationId?: string
        last_message?: string
        last_message_at?: string
      }>
      const { conversationId, last_message, last_message_at } = ce.detail || {}
      if (!conversationId) return
      setConversations((prev) => {
        if (!prev.some((c) => c.id === conversationId)) return prev
        const updated = prev.map((c) =>
          c.id === conversationId
            ? {
                ...c,
                lastMessage: last_message ?? c.lastMessage,
                last_message_at: last_message_at ?? c.last_message_at
              }
            : c
        )
        return sortConversationsDesc(updated)
      })
    }
    window.addEventListener("tj-conversation-updated", handler)
    return () => window.removeEventListener("tj-conversation-updated", handler)
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
    await fetchAllUsers(user.id)
    setLoading(false)
  }

  const fetchConversations = useCallback(async (userId: string) => {
    const { data: rows } = await supabase
      .from("conversation_participants")
      .select(`
        conversation_id,
        conversations (
          id,
          is_group,
          is_pinned,
          name,
          avatar_url,
          last_message,
          last_message_at
        )
      `)
      .eq("user_id", userId)

    if (!rows || rows.length === 0) {
      setConversations([])
      return
    }

    const convoIds = rows.map((p: any) => p.conversation_id)

    const { data: msgRows } = await supabase
      .from("messages")
      .select("conversation_id, seen_by, sender_id")
      .in("conversation_id", convoIds)

    const unreadByConvo: Record<string, number> = {}
    for (const cid of convoIds) unreadByConvo[cid] = 0
    for (const m of msgRows || []) {
      const cid = m.conversation_id as string
      if (!m.sender_id || m.sender_id === userId) continue
      const seen = Array.isArray(m.seen_by) ? m.seen_by : []
      if (seen.includes(userId)) continue
      unreadByConvo[cid] = (unreadByConvo[cid] || 0) + 1
    }

    const convoData = await Promise.all(
      convoIds.map(async (convoId) => {
        const convoRow = rows.find((r: any) => r.conversation_id === convoId)
        const convoMeta = Array.isArray(convoRow?.conversations)
          ? convoRow?.conversations?.[0]
          : convoRow?.conversations

        const { data: participants } = await supabase
          .from("conversation_participants")
          .select(`
            user_id,
            profiles (id, username, avatar_url, name)
          `)
          .eq("conversation_id", convoId)

        const otherUser = participants?.find((u: any) => u.user_id !== userId)
        const rawProfile = otherUser?.profiles
        const profile = Array.isArray(rawProfile) ? rawProfile[0] : rawProfile

        const { data: messages } = await supabase
          .from("messages")
          .select("content, created_at")
          .eq("conversation_id", convoId)
          .order("created_at", { ascending: false })
          .limit(1)

        const isGroup = convoMeta?.is_group === true
        const displayName = isGroup
          ? convoMeta?.name || "Group Chat"
          : profile?.username || "user"

        return {
          id: convoId,
          is_group: isGroup,
          is_pinned: convoMeta?.is_pinned === true,
          name: convoMeta?.name || null,
          displayName,
          username: profile?.username || "user",
          avatar_url: isGroup
            ? convoMeta?.avatar_url ?? null
            : profile?.avatar_url ?? null,
          participants: participants || [],
          lastMessage:
            convoMeta?.last_message || messages?.[0]?.content || "No messages yet",
          last_message_at:
            convoMeta?.last_message_at || messages?.[0]?.created_at || null,
          unreadCount: unreadByConvo[convoId] ?? 0,
        }
      })
    )

    setConversations(sortConversationsDesc(convoData || []))
  }, [])

  useEffect(() => {
    if (!user?.id) return

    const channel = supabase.channel(`messages-list-${user.id}`)

    channel.on(
      "postgres_changes",
      {
        event: "INSERT",
        schema: "public",
        table: "messages",
      },
      () => {
        void fetchConversations(user.id)
      }
    )

    channel.on(
      "postgres_changes",
      {
        event: "UPDATE",
        schema: "public",
        table: "messages",
      },
      () => {
        void fetchConversations(user.id)
      }
    )

    channel.subscribe()

    return () => {
      void supabase.removeChannel(channel)
    }
  }, [user?.id, fetchConversations])

  async function fetchAllUsers(currentUserId: string) {
    const { data } = await supabase
      .from("profiles")
      .select("id, username, name, avatar_url")
      .neq("id", currentUserId)
      .order("username", { ascending: true })
      .limit(100)

    setAllUsers(data || [])
  }

  async function createGroupChat() {
    if (!user || groupSelectedUsers.length === 0 || !groupName.trim()) return

    setCreatingGroup(true)
    const { data: convo } = await supabase
      .from("conversations")
      .insert({
        is_group: true,
        name: groupName.trim()
      })
      .select()
      .single()

    if (!convo?.id) {
      setCreatingGroup(false)
      return
    }

    const participants = groupSelectedUsers.map((u) => ({
      conversation_id: convo.id,
      user_id: u.id
    }))

    participants.push({
      conversation_id: convo.id,
      user_id: user.id
    })

    await supabase
      .from("conversation_participants")
      .insert(participants)

    const now = new Date().toISOString()
    const newConversation = {
      id: convo.id,
      is_group: true,
      is_pinned: false,
      name: groupName.trim(),
      displayName: groupName.trim(),
      username: "user",
      avatar_url: null as string | null,
      participants: [],
      lastMessage: "No messages yet",
      last_message_at: now,
      unreadCount: 0,
    }

    setConversations((prev) => mergeNewConversation(prev, newConversation))

    setShowGroupModal(false)
    setGroupSelectedUsers([])
    setGroupSearchQuery("")
    setGroupResults([])
    setGroupName("")
    setCreatingGroup(false)
    router.push(`/messages/${convo.id}`)
  }

  async function findExistingDM(currentUserId: string, otherUserId: string) {
    const { data: myRows } = await supabase
      .from("conversation_participants")
      .select("conversation_id")
      .eq("user_id", currentUserId)

    const ids = [...new Set(myRows?.map((r) => r.conversation_id) || [])]
    for (const convoId of ids) {
      const { data: meta } = await supabase
        .from("conversations")
        .select("id, is_group")
        .eq("id", convoId)
        .maybeSingle()

      if (!meta || meta.is_group) continue

      const { data: parts } = await supabase
        .from("conversation_participants")
        .select("user_id")
        .eq("conversation_id", convoId)

      const uidSet = new Set(parts?.map((p) => p.user_id))
      if (
        uidSet.size === 2 &&
        uidSet.has(currentUserId) &&
        uidSet.has(otherUserId)
      ) {
        return convoId as string
      }
    }
    return null
  }

  async function startDMChat() {
    const selectedDmUserId = dmSelectedUsers[0]?.id
    if (!user || !selectedDmUserId) return

    setCreatingDM(true)
    const existingId = await findExistingDM(user.id, selectedDmUserId)

    if (existingId) {
      setShowDMModal(false)
      setDmSelectedUsers([])
      setDmSearchQuery("")
      setDmResults([])
      setCreatingDM(false)
      router.push(`/messages/${existingId}`)
      return
    }

    const { data: convo, error } = await supabase
      .from("conversations")
      .insert({ is_group: false })
      .select()
      .single()

    if (error || !convo?.id) {
      console.error("DM conversation create error:", error)
      setCreatingDM(false)
      return
    }

    await supabase.from("conversation_participants").insert([
      { conversation_id: convo.id, user_id: user.id },
      { conversation_id: convo.id, user_id: selectedDmUserId },
    ])

    const other =
      dmSelectedUsers[0] ?? allUsers.find((u) => u.id === selectedDmUserId)
    const now = new Date().toISOString()
    const newConversation = {
      id: convo.id,
      is_group: false,
      is_pinned: false,
      name: null as string | null,
      displayName: other?.username || "user",
      username: other?.username || "user",
      avatar_url: other?.avatar_url ?? null,
      participants: [],
      lastMessage: "No messages yet",
      last_message_at: now,
      unreadCount: 0,
    }

    setConversations((prev) => mergeNewConversation(prev, newConversation))

    setShowDMModal(false)
    setDmSelectedUsers([])
    setDmSearchQuery("")
    setDmResults([])
    setCreatingDM(false)
    router.push(`/messages/${convo.id}`)
  }

  const filteredConversations = conversations.filter((c) =>
    (c.displayName || c.username).toLowerCase().includes(search.toLowerCase())
  )

  async function handleDeleteChat(conversationId: string) {
    if (!confirm("Delete this chat?")) return
    if (!user) return

    await supabase
      .from("conversation_participants")
      .delete()
      .eq("conversation_id", conversationId)
      .eq("user_id", user.id)

    setConversations((prev) => prev.filter((c) => c.id !== conversationId))
    setOpenConvoMenuId(null)
  }

  async function togglePinChat(conversationId: string, currentState: boolean) {
    await supabase
      .from("conversations")
      .update({ is_pinned: !currentState })
      .eq("id", conversationId)

    if (user?.id) {
      await fetchConversations(user.id)
    }
    setOpenConvoMenuId(null)
  }

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-[#0f172a] bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white px-6 pb-6 pt-4">

        <div className="max-w-3xl mx-auto">

          <h1 className="text-2xl font-semibold mb-4">
            Messages
          </h1>

          <div className="mt-2 mb-4 flex justify-start gap-2 md:mt-3">
            
            <button
              type="button"
              onClick={openDMModal}
              className="w-auto rounded-lg bg-blue-500 px-3 py-2 text-white hover:bg-blue-600"
            >
              New Chat
            </button>
            <button
              type="button"
              onClick={() => setShowGroupModal(true)}
              className="w-auto rounded-lg bg-blue-500 px-3 py-2 text-white hover:bg-blue-600"
            >
              New Group
            </button>
          </div>

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
                  className="relative bg-white/5 border border-white/10 p-4 rounded-xl cursor-pointer hover:bg-white/10 transition"
                >
                  <button
                    type="button"
                    aria-label="Conversation options"
                    onClick={(e) => {
                      e.stopPropagation()
                      setOpenConvoMenuId(
                        openConvoMenuId === c.id ? null : c.id
                      )
                    }}
                    className="absolute right-3 top-3 z-10 px-2 py-1 rounded bg-black/40 hover:bg-black/60 text-sm text-white cursor-pointer"
                  >
                    ⋯
                  </button>
                  {openConvoMenuId === c.id ? (
                    <div
                      className="absolute right-3 top-10 z-20 w-40 rounded-lg border border-white/10 bg-[#0f172a] py-1 shadow-lg"
                      onClick={(e) => e.stopPropagation()}
                    >
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation()
                          void togglePinChat(c.id, c.is_pinned === true)
                        }}
                        className="w-full px-3 py-2 text-left text-sm text-white hover:bg-[#1f2937] cursor-pointer"
                      >
                        {c.is_pinned ? "Unpin Chat" : "Pin Chat"}
                      </button>
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation()
                          handleDeleteChat(c.id)
                        }}
                        className="w-full px-3 py-2 text-left text-sm text-white hover:bg-white/10 cursor-pointer"
                      >
                        Delete Chat
                      </button>
                    </div>
                  ) : null}
                  <div className="flex items-center gap-3 pr-10">

                    {c.avatar_url ? (
                      <img
                        src={c.avatar_url}
                        className="w-10 h-10 rounded-full object-cover hover:scale-105 transition"
                      />
                    ) : (
                      <div className="w-10 h-10 rounded-full bg-gray-600" />
                    )}

                    <div className="min-w-0 flex-1">
                      <p className="text-emerald-400 font-semibold">
                        {c.is_group ? c.name || c.displayName : `@${c.username}`}
                        {c.is_pinned ? (
                          <span className="ml-2 text-xs text-yellow-400">📌</span>
                        ) : null}
                      </p>

                      <p className="text-sm text-gray-400 truncate">
                        {c.lastMessage}
                      </p>
                    </div>

                    {c.unreadCount > 0 ? (
                      <span className="ml-auto shrink-0 bg-red-500 text-white text-xs px-2 py-1 rounded-full tabular-nums">
                        {c.unreadCount > 9 ? "9+" : c.unreadCount}
                      </span>
                    ) : null}

                  </div>
                </div>
              ))}

            </div>
          )}

        </div>

      </div>

      {showGroupModal && (
        <div
          className="fixed inset-0 bg-black/50 backdrop-blur-sm flex items-center justify-center z-50 p-4 text-white"
          onClick={() => setShowGroupModal(false)}
        >
          <div
            className="bg-[#0f172a] border border-gray-600 rounded-2xl p-6 w-full max-w-lg shadow-2xl text-white"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="text-white text-xl font-semibold mb-4">
              Create Group Chat
            </h2>

            <input
              value={groupName}
              onChange={(e) => setGroupName(e.target.value)}
              placeholder="Group name"
              className="w-full mb-3 p-3 rounded-lg bg-[#1e293b] text-white border border-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500"
            />

            <input
              type="text"
              placeholder="Search users..."
              value={groupSearchQuery}
              onChange={(e) => setGroupSearchQuery(e.target.value)}
              className="w-full mb-3 p-3 rounded-lg bg-[#1e293b] text-white border border-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500"
            />

            <div className="max-h-64 overflow-y-auto space-y-2 mb-4">
              {(groupSearchQuery.trim() ? groupResults : allUsers).map((u) => {
                const selected = groupSelectedUsers.some((su) => su.id === u.id)
                return (
                  <button
                    key={u.id}
                    type="button"
                    onClick={() =>
                      setGroupSelectedUsers((prev) =>
                        selected
                          ? prev.filter((entry) => entry.id !== u.id)
                          : [...prev, u]
                      )
                    }
                    className={`flex w-full items-center gap-3 rounded-lg p-3 cursor-pointer transition ${
                      selected
                        ? "bg-blue-500/20 ring-1 ring-blue-400/40"
                        : "hover:bg-[#1e293b]"
                    }`}
                  >
                    <img
                      src={u.avatar_url || "/default-avatar.png"}
                      alt=""
                      className="h-8 w-8 shrink-0 rounded-full object-cover hover:scale-105 transition"
                    />
                    <div className="flex flex-col text-left">
                      <span
                        className={`text-sm font-medium ${
                          selected ? "text-blue-300" : "text-white"
                        }`}
                      >
                        {u.name || u.username}
                      </span>
                      <span className="text-xs text-gray-400">@{u.username}</span>
                    </div>
                  </button>
                )
              })}
            </div>

            <div className="mt-2 flex flex-wrap gap-2">
              {groupSelectedUsers.map((selectedUser) => (
                <div
                  key={selectedUser.id}
                  className="flex items-center gap-1 rounded bg-blue-500 px-2 py-1 text-xs"
                >
                  {selectedUser.username}
                  <button
                    type="button"
                    onClick={() =>
                      setGroupSelectedUsers((prev) =>
                        prev.filter((u) => u.id !== selectedUser.id)
                      )
                    }
                  >
                    ×
                  </button>
                </div>
              ))}
            </div>

            <div className="mt-4 flex justify-end gap-3">
              <button
                type="button"
                onClick={() => setShowGroupModal(false)}
                className="rounded-lg bg-gray-700 px-4 py-2 text-white hover:bg-gray-600"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={createGroupChat}
                disabled={creatingGroup}
                className="rounded-lg bg-blue-500 px-4 py-2 text-white hover:bg-blue-600 disabled:opacity-50"
              >
                {creatingGroup ? "Creating..." : "Create"}
              </button>
            </div>
          </div>
        </div>
      )}

      {showDMModal && (
        <div
          className="fixed inset-0 bg-black/50 backdrop-blur-sm flex items-center justify-center z-50 p-4 text-white"
          onClick={() => setShowDMModal(false)}
        >
          <div
            className="bg-[#0f172a] border border-gray-600 rounded-2xl p-6 w-full max-w-lg shadow-2xl text-white"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="text-white text-xl font-semibold mb-4">
              New Chat
            </h2>

            <input
              type="text"
              placeholder="Search users..."
              value={dmSearchQuery}
              onChange={(e) => setDmSearchQuery(e.target.value)}
              className="w-full mb-3 p-3 rounded-lg bg-[#1e293b] text-white border border-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500"
            />

            <div className="max-h-64 overflow-y-auto space-y-2 mb-4">
              {(dmSearchQuery.trim() ? dmResults : allUsers).map((u) => {
                const selected = dmSelectedUsers.some((su) => su.id === u.id)
                return (
                  <button
                    key={u.id}
                    type="button"
                    onClick={() => setDmSelectedUsers(selected ? [] : [u])}
                    className={`flex w-full items-center gap-3 rounded-lg p-3 cursor-pointer transition ${
                      selected
                        ? "bg-blue-500/20 ring-1 ring-blue-400/40"
                        : "hover:bg-[#1e293b]"
                    }`}
                  >
                    <img
                      src={u.avatar_url || "/default-avatar.png"}
                      alt=""
                      className="h-8 w-8 shrink-0 rounded-full object-cover hover:scale-105 transition"
                    />
                    <div className="flex flex-col text-left">
                      <span
                        className={`text-sm font-medium ${
                          selected ? "text-blue-300" : "text-white"
                        }`}
                      >
                        {u.name || u.username}
                      </span>
                      <span className="text-xs text-gray-400">@{u.username}</span>
                    </div>
                  </button>
                )
              })}
            </div>

            <div className="mt-2 flex flex-wrap gap-2">
              {dmSelectedUsers.map((selectedUser) => (
                <div
                  key={selectedUser.id}
                  className="flex items-center gap-1 rounded bg-blue-500 px-2 py-1 text-xs"
                >
                  {selectedUser.username}
                  <button
                    type="button"
                    onClick={() => setDmSelectedUsers([])}
                  >
                    ×
                  </button>
                </div>
              ))}
            </div>

            <div className="mt-4 flex justify-end gap-3">
              <button
                type="button"
                onClick={() => setShowDMModal(false)}
                className="rounded-lg bg-gray-700 px-4 py-2 text-white hover:bg-gray-600"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={startDMChat}
                disabled={creatingDM || dmSelectedUsers.length === 0}
                className="rounded-lg bg-blue-500 px-4 py-2 text-white hover:bg-blue-600 disabled:opacity-50"
              >
                {creatingDM ? "Opening..." : "Start chat"}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}