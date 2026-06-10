"use client"

import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { supabase } from "../../../lib/supabaseClient"
import { isConversationParticipant } from "../../../lib/conversationAccess"
import {
  countUnreadFromRows,
  fetchUnreadCountForConversation as fetchUnreadCountForConversationShared,
  fetchUnreadMessageRows,
  normalizeSeenBy,
} from "../../../lib/messageUnread"
import { useRouter } from "next/navigation"
import MessagesConversationList from "../../components/messages/MessagesConversationList"

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

function previewFromMessage(row: {
  content?: string | null
  image_url?: string | null
  type?: string | null
  deleted_for_everyone?: boolean | null
  is_system?: boolean | null
}): string {
  if (row.deleted_for_everyone) return "Message deleted"
  if (row.content?.trim()) return row.content.trim()
  if (row.image_url) return "Image"
  if (row.type === "trade") return "Shared a trade"
  if (row.type === "post") return "Shared a post"
  return "New message"
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
  const userIdRef = useRef<string | null>(null)
  const conversationIdsRef = useRef<Set<string>>(new Set())
  const unreadRefreshTimersRef = useRef<
    Record<string, ReturnType<typeof setTimeout>>
  >({})

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

  const fetchAllUsers = useCallback(async (currentUserId: string) => {
    const { data } = await supabase
      .from("profiles")
      .select("id, username, name, avatar_url")
      .neq("id", currentUserId)
      .order("username", { ascending: true })
      .limit(100)

    setAllUsers(data || [])
  }, [])

  useEffect(() => {
    if (!user?.id || (!showGroupModal && !showDMModal)) return
    void fetchAllUsers(user.id)
  }, [showGroupModal, showDMModal, user?.id, fetchAllUsers])

  useEffect(() => {
    init()
  }, [])

  const markMessageNotificationsRead = useCallback(
    async (currentUserId: string, reason: "page-open" | "chat-open") => {
      console.log("[messages] mark read start", {
        reason,
        userId: currentUserId,
        type: "message",
      })

      const { data, error, count } = await supabase
        .from("notifications")
        .update({ read: true })
        .eq("user_id", currentUserId)
        .eq("type", "message")
        .eq("read", false)
        .select("id,type", { count: "exact" })

      if (error) {
        console.error("[messages] mark read error:", {
          reason,
          userId: currentUserId,
          error,
        })
        return
      }

      console.log("[messages] mark read success", {
        reason,
        userId: currentUserId,
        updated: count ?? data?.length ?? 0,
      })

      window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
    },
    []
  )

  const markConversationRead = useCallback(
    async (currentUserId: string, conversationId: string) => {
      console.log("[messages] mark conversation read start", {
        userId: currentUserId,
        conversationId,
      })

      const { data: rows, error: fetchErr } = await supabase
        .from("messages")
        .select("id, sender_id, seen_by")
        .eq("conversation_id", conversationId)

      if (fetchErr) {
        console.error("[messages] mark conversation read fetch error:", fetchErr)
        return
      }

      let updates = 0
      for (const row of rows || []) {
        if (!row.sender_id || row.sender_id === currentUserId) continue
        const seenBy = normalizeSeenBy(row.seen_by)
        if (seenBy.includes(currentUserId)) continue
        const nextSeenBy = [...seenBy, currentUserId]

        console.log("[messages] seen_by update attempt", {
          messageId: row.id,
          oldSeenBy: seenBy,
          newSeenBy: nextSeenBy,
        })

        const { error: upErr } = await supabase
          .from("messages")
          .update({ seen_by: nextSeenBy })
          .eq("id", row.id)

        if (upErr) {
          console.error("[messages] mark conversation read update error:", {
            messageId: row.id,
            error: upErr,
          })
          continue
        }
        updates += 1
      }

      const { data: verifyRows, error: verifyErr } = await supabase
        .from("messages")
        .select("id, sender_id, seen_by")
        .eq("conversation_id", conversationId)

      if (verifyErr) {
        console.error("[messages] mark conversation read verify error:", verifyErr)
      } else {
        const remainingUnread = (verifyRows || []).filter((r) => {
          if (!r.sender_id || r.sender_id === currentUserId) return false
          const seen = normalizeSeenBy(r.seen_by)
          return !seen.includes(currentUserId)
        })
        console.log("[messages] mark conversation read verify", {
          userId: currentUserId,
          conversationId,
          remainingUnreadCount: remainingUnread.length,
          remainingUnreadMessageIds: remainingUnread.map((r) => r.id),
        })
      }

      console.log("[messages] mark conversation read success", {
        userId: currentUserId,
        conversationId,
        updatedMessages: updates,
        unreadBefore:
          (rows || []).filter((r) => {
            if (!r.sender_id || r.sender_id === currentUserId) return false
            const seen = Array.isArray(r.seen_by) ? r.seen_by : []
            return !seen.includes(currentUserId)
          }).length,
      })
    },
    []
  )

  useEffect(() => {
    if (!user?.id) return
    void markMessageNotificationsRead(user.id, "page-open")
  }, [user?.id, markMessageNotificationsRead])

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

    const { data: participantRows } = await supabase
      .from("conversation_participants")
      .select(`
        conversation_id,
        user_id,
        profiles (id, username, avatar_url, name)
      `)
      .in("conversation_id", convoIds)

    const participantsByConvo = new Map<string, any[]>()
    for (const row of participantRows || []) {
      const cid = row.conversation_id as string
      const list = participantsByConvo.get(cid) || []
      list.push(row)
      participantsByConvo.set(cid, list)
    }

    const msgRows = await fetchUnreadMessageRows(userId, convoIds)

    const unreadByConvo: Record<string, number> = {}
    for (const cid of convoIds) unreadByConvo[cid] = 0
    for (const m of msgRows || []) {
      const cid = m.conversation_id as string
      if (!m.sender_id || m.sender_id === userId) continue
      const seen = normalizeSeenBy(m.seen_by)
      if (seen.includes(userId)) continue
      unreadByConvo[cid] = (unreadByConvo[cid] || 0) + 1
    }

    const convoData = convoIds.map((convoId) => {
      const convoRow = rows.find((r: any) => r.conversation_id === convoId)
      const convoMeta = Array.isArray(convoRow?.conversations)
        ? convoRow?.conversations?.[0]
        : convoRow?.conversations

      const participants = participantsByConvo.get(convoId) || []
      const otherUser = participants.find((u: any) => u.user_id !== userId)
      const rawProfile = otherUser?.profiles
      const profile = Array.isArray(rawProfile) ? rawProfile[0] : rawProfile

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
        participants,
        lastMessage: convoMeta?.last_message || "No messages yet",
        last_message_at: convoMeta?.last_message_at || null,
        unreadCount: unreadByConvo[convoId] ?? 0,
      }
    })

    setConversations(sortConversationsDesc(convoData))
  }, [])

  const fetchUnreadCountForConversation = useCallback(
    async (userId: string, conversationId: string) =>
      fetchUnreadCountForConversationShared(userId, conversationId),
    []
  )

  useEffect(() => {
    userIdRef.current = user?.id ?? null
  }, [user?.id])

  useEffect(() => {
    conversationIdsRef.current = new Set(conversations.map((c) => String(c.id)))
  }, [conversations])

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
      (payload) => {
        const row = payload.new as {
          conversation_id?: string
          sender_id?: string | null
          content?: string | null
          image_url?: string | null
          type?: string | null
          created_at?: string | null
          seen_by?: unknown
          deleted_for_everyone?: boolean | null
          is_system?: boolean | null
        }
        const uid = userIdRef.current
        const convoId = row?.conversation_id
        if (!uid || !convoId) return

        if (!conversationIdsRef.current.has(convoId)) {
          void fetchConversations(uid)
          return
        }

        setConversations((prev) => {
          if (!prev.some((c) => c.id === convoId)) return prev

          const preview = previewFromMessage(row)
          const createdAt = row.created_at ?? new Date().toISOString()
          const fromOther = !!row.sender_id && row.sender_id !== uid
          const isUnread =
            fromOther && !normalizeSeenBy(row.seen_by).includes(uid)

          const updated = prev.map((c) => {
            if (c.id !== convoId) return c
            return {
              ...c,
              lastMessage: preview,
              last_message_at: createdAt,
              unreadCount: isUnread
                ? (c.unreadCount ?? 0) + 1
                : c.unreadCount ?? 0,
            }
          })
          return sortConversationsDesc(updated)
        })
      }
    )

    channel.on(
      "postgres_changes",
      {
        event: "UPDATE",
        schema: "public",
        table: "messages",
      },
      (payload) => {
        const row = payload.new as {
          conversation_id?: string
          seen_by?: unknown
        }
        const oldRow = payload.old as { seen_by?: unknown } | undefined
        const uid = userIdRef.current
        const convoId = row?.conversation_id
        if (!uid || !convoId) return
        if (!conversationIdsRef.current.has(convoId)) return

        const seenChanged =
          JSON.stringify(normalizeSeenBy(oldRow?.seen_by)) !==
          JSON.stringify(normalizeSeenBy(row.seen_by))
        if (!seenChanged) return

        const scheduleUnreadRefresh = () => {
          const existing = unreadRefreshTimersRef.current[convoId]
          if (existing) clearTimeout(existing)
          unreadRefreshTimersRef.current[convoId] = setTimeout(() => {
            delete unreadRefreshTimersRef.current[convoId]
            void (async () => {
              const count = await fetchUnreadCountForConversation(uid, convoId)
              setConversations((prev) =>
                prev.map((c) =>
                  c.id === convoId ? { ...c, unreadCount: count } : c
                )
              )
            })()
          }, 200)
        }

        scheduleUnreadRefresh()
      }
    )

    channel.subscribe()

    return () => {
      Object.values(unreadRefreshTimersRef.current).forEach(clearTimeout)
      unreadRefreshTimersRef.current = {}
      void supabase.removeChannel(channel)
    }
  }, [user?.id, fetchConversations, fetchUnreadCountForConversation])

  const openConversation = useCallback(
    async (conversationId: string) => {
      if (user?.id) {
        await markConversationRead(user.id, conversationId)
        await markMessageNotificationsRead(user.id, "chat-open")
        await fetchConversations(user.id)
        setConversations((prev) =>
          prev.map((c) =>
            c.id === conversationId ? { ...c, unreadCount: 0 } : c
          )
        )
      }
      router.push(`/messages/${conversationId}`)
    },
    [
      user?.id,
      markConversationRead,
      markMessageNotificationsRead,
      fetchConversations,
      router,
    ]
  )

  const handleOpenConversation = useCallback(
    (conversationId: string) => {
      void openConversation(conversationId)
    },
    [openConversation]
  )

  const handleToggleConvoMenu = useCallback((conversationId: string) => {
    setOpenConvoMenuId((prev) => (prev === conversationId ? null : conversationId))
  }, [])

  const handleDeleteConversation = useCallback(
    async (conversationId: string) => {
      if (!confirm("Delete this chat?")) return
      if (!user) return

      await supabase
        .from("conversation_participants")
        .delete()
        .eq("conversation_id", conversationId)
        .eq("user_id", user.id)

      setConversations((prev) => prev.filter((c) => c.id !== conversationId))
      setOpenConvoMenuId(null)
    },
    [user]
  )

  const handlePinConversation = useCallback(
    async (conversationId: string, currentState: boolean) => {
      if (!user?.id) return

      const allowed = await isConversationParticipant(conversationId, user.id)
      if (!allowed) {
        setOpenConvoMenuId(null)
        return
      }

      await supabase
        .from("conversations")
        .update({ is_pinned: !currentState })
        .eq("id", conversationId)

      await fetchConversations(user.id)
      setOpenConvoMenuId(null)
    },
    [user?.id, fetchConversations]
  )

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

  const filteredConversations = useMemo(() => {
    const query = search.trim().toLowerCase()
    if (!query) return conversations
    return conversations.filter((c) =>
      (c.displayName || c.username).toLowerCase().includes(query)
    )
  }, [conversations, search])

  return (
    <>
      <div className="flex h-[calc(100dvh-4rem)] min-h-0 flex-col overflow-hidden bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white px-6 pb-6 pt-0">

        <div className="mx-auto flex h-full min-h-0 w-full max-w-3xl flex-col">

          <h1 className="mb-4 shrink-0 text-2xl font-semibold">
            Messages
          </h1>

          <div className="mt-2 mb-4 flex shrink-0 justify-start gap-2 md:mt-3">
            
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
            className="mb-6 w-full shrink-0 rounded border border-white/10 bg-black p-3 focus:border-emerald-400 focus:outline-none"
          />

          <div className="min-h-0 flex-1 overflow-y-auto">
            {loading ? (
              <p className="text-gray-400">Loading...</p>
            ) : filteredConversations.length === 0 ? (
              <p className="text-gray-400">No conversations found</p>
            ) : (
              <MessagesConversationList
                conversations={filteredConversations}
                openConvoMenuId={openConvoMenuId}
                onOpen={handleOpenConversation}
                onToggleMenu={handleToggleConvoMenu}
                onPin={handlePinConversation}
                onDelete={handleDeleteConversation}
              />
            )}
          </div>

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
                      loading="lazy"
                      decoding="async"
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
                      loading="lazy"
                      decoding="async"
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