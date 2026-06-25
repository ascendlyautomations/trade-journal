"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { supabase } from "../../../lib/supabaseClient"
import {
  isConversationParticipant,
  newConversationId,
} from "../../../lib/conversationAccess"
import { ensureDmConversation } from "@/lib/dmConversation"
import { buildDmThreadPath, groupThreadPath } from "@/lib/messageRoutes"
import { normalizeProfileUsername } from "@/lib/profileUsername"
import {
  countUnreadFromRows,
  dispatchUnreadMessagesRefresh,
  fetchUnreadCountForConversation as fetchUnreadCountForConversationShared,
  fetchUnreadMessageRows,
  markConversationUnread,
  normalizeSeenBy,
} from "../../../lib/messageUnread"
import {
  applyInboxPatchesToConversations,
  CONVERSATION_UPDATED_EVENT,
  INBOX_PATCHES_STORAGE_KEY,
  mergeConversationInboxFields,
  readInboxPatches,
} from "@/lib/conversationInboxSync"
import { useRouter } from "next/navigation"
import MessagesConversationList from "../../components/messages/MessagesConversationList"
import EmptyState from "../../components/ui/EmptyState"

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
            ? mergeConversationInboxFields(c, {
                last_message,
                last_message_at,
              })
            : c
        )
        return sortConversationsDesc(updated)
      })
    }
    window.addEventListener(CONVERSATION_UPDATED_EVENT, handler)
    return () => window.removeEventListener(CONVERSATION_UPDATED_EVENT, handler)
  }, [])

  useEffect(() => {
    function applyStoredPatches() {
      const patches = readInboxPatches()
      if (Object.keys(patches).length === 0) return
      setConversations((prev) =>
        sortConversationsDesc(applyInboxPatchesToConversations(prev, patches))
      )
    }

    function onStorage(event: StorageEvent) {
      if (event.key === INBOX_PATCHES_STORAGE_KEY) applyStoredPatches()
    }

    function onVisibilityChange() {
      if (document.visibilityState === "visible") applyStoredPatches()
    }

    window.addEventListener("storage", onStorage)
    document.addEventListener("visibilitychange", onVisibilityChange)
    return () => {
      window.removeEventListener("storage", onStorage)
      document.removeEventListener("visibilitychange", onVisibilityChange)
    }
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
      return []
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
        otherUserId: isGroup ? null : (profile?.id ?? otherUser?.user_id ?? null),
        profileUserId: isGroup
          ? null
          : (profile?.id ?? otherUser?.user_id ?? null),
        avatar_url: isGroup
          ? convoMeta?.avatar_url ?? null
          : profile?.avatar_url ?? null,
        participants,
        lastMessage: convoMeta?.last_message || "No messages yet",
        last_message_at: convoMeta?.last_message_at || null,
        unreadCount: unreadByConvo[convoId] ?? 0,
      }
    })

    const sorted = sortConversationsDesc(
      applyInboxPatchesToConversations(convoData)
    )
    setConversations(sorted)
    return sorted
  }, [])

  const fetchUnreadCountForConversation = useCallback(
    async (userId: string, conversationId: string) =>
      fetchUnreadCountForConversationShared(userId, conversationId),
    []
  )

  useEffect(() => {
    if (!user?.id) return

    const uid = user.id

    const refresh = () => {
      if (document.hidden) return
      void fetchConversations(uid)
    }

    const onWindowFocus = () => refresh()

    let intervalId: ReturnType<typeof setInterval> | null = null

    const stopInterval = () => {
      if (intervalId != null) {
        clearInterval(intervalId)
        intervalId = null
      }
    }

    const startInterval = () => {
      stopInterval()
      if (document.hidden) return
      intervalId = window.setInterval(refresh, 45_000)
    }

    const onVisibilityChange = () => {
      if (document.visibilityState === "visible") {
        refresh()
        startInterval()
      } else {
        stopInterval()
      }
    }

    window.addEventListener("focus", onWindowFocus)
    document.addEventListener("visibilitychange", onVisibilityChange)
    startInterval()

    return () => {
      window.removeEventListener("focus", onWindowFocus)
      document.removeEventListener("visibilitychange", onVisibilityChange)
      stopInterval()
    }
  }, [user?.id, fetchConversations])

  const openConversation = useCallback(
    async (conversationId: string) => {
      let list = conversations

      if (user?.id) {
        await markConversationRead(user.id, conversationId)
        await markMessageNotificationsRead(user.id, "chat-open")
        list = (await fetchConversations(user.id)) ?? list
        setConversations((prev) =>
          prev.map((c) =>
            c.id === conversationId ? { ...c, unreadCount: 0 } : c
          )
        )
      }

      const item = list.find((c) => c.id === conversationId)
      let path = groupThreadPath(conversationId)
      if (item && !item.is_group) {
        const normalized = normalizeProfileUsername(item.username ?? "")
        path =
          normalized && item.username !== "user"
            ? buildDmThreadPath(normalized)
            : groupThreadPath(conversationId)
      }
      router.push(path)
    },
    [
      user?.id,
      conversations,
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

  const handleMarkConversationUnread = useCallback(
    async (conversationId: string) => {
      if (!user?.id) return

      setOpenConvoMenuId(null)

      setConversations((prev) =>
        prev.map((c) => {
          if (c.id !== conversationId) return c
          const current = c.unreadCount ?? 0
          return {
            ...c,
            unreadCount: current === 0 ? 1 : current + 1,
          }
        })
      )
      dispatchUnreadMessagesRefresh()

      const result = await markConversationUnread(user.id, conversationId)
      if (!result.ok) {
        const count = await fetchUnreadCountForConversation(
          user.id,
          conversationId
        )
        setConversations((prev) =>
          prev.map((c) =>
            c.id === conversationId ? { ...c, unreadCount: count } : c
          )
        )
        dispatchUnreadMessagesRefresh()
        return
      }

      setConversations((prev) =>
        prev.map((c) =>
          c.id === conversationId
            ? { ...c, unreadCount: result.unreadCount }
            : c
        )
      )
      dispatchUnreadMessagesRefresh()
    },
    [user?.id, fetchUnreadCountForConversation]
  )

  async function createGroupChat() {
    if (!user || groupSelectedUsers.length === 0 || !groupName.trim()) return

    setCreatingGroup(true)
    const conversationId = newConversationId()
    const convoPayload = {
      id: conversationId,
      is_group: true,
      name: groupName.trim(),
    }
    const { error: convoErr } = await supabase
      .from("conversations")
      .insert(convoPayload)

    if (convoErr) {
      logSupabaseError("createGroupChat conversations insert", convoErr, {
        table: "conversations",
        query: "insert",
        payload: convoPayload,
        userId: user.id,
      })
      setCreatingGroup(false)
      return
    }

    const participants = groupSelectedUsers.map((u) => ({
      conversation_id: conversationId,
      user_id: u.id
    }))

    participants.push({
      conversation_id: conversationId,
      user_id: user.id
    })

    const { error: participantsErr } = await supabase
      .from("conversation_participants")
      .insert(participants)
    if (participantsErr) {
      logSupabaseError("createGroupChat conversation_participants insert", participantsErr, {
        table: "conversation_participants",
        query: "insert",
        payload: participants,
        userId: user.id,
        conversationId,
      })
      setCreatingGroup(false)
      return
    }

    const now = new Date().toISOString()
    const newConversation = {
      id: conversationId,
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
    router.push(groupThreadPath(conversationId))
  }

  async function startDMChat() {
    const selectedDmUserId = dmSelectedUsers[0]?.id
    if (!user || !selectedDmUserId) return

    setCreatingDM(true)
    const result = await ensureDmConversation(
      supabase,
      user.id,
      selectedDmUserId
    )

    if (!result.ok) {
      if (result.phase === "conversation") {
        logSupabaseError("startDMChat conversations insert", result.error, {
          table: "conversations",
          query: "insert",
          payload: { id: result.conversationId, is_group: false },
          userId: user.id,
          otherUserId: selectedDmUserId,
        })
      } else {
        logSupabaseError(
          "startDMChat conversation_participants insert",
          result.error,
          {
            table: "conversation_participants",
            query: "insert",
            payload: [
              { conversation_id: result.conversationId, user_id: user.id },
              {
                conversation_id: result.conversationId,
                user_id: selectedDmUserId,
              },
            ],
            userId: user.id,
            conversationId: result.conversationId,
            otherUserId: selectedDmUserId,
          }
        )
      }
      setCreatingDM(false)
      return
    }

    const { conversationId } = result

    if (!result.existing) {
      const other =
        dmSelectedUsers[0] ?? allUsers.find((u) => u.id === selectedDmUserId)
      const now = new Date().toISOString()
      const newConversation = {
        id: conversationId,
        is_group: false,
        is_pinned: false,
        name: null as string | null,
        displayName: other?.username || "user",
        username: other?.username || "user",
        otherUserId: selectedDmUserId,
        avatar_url: other?.avatar_url ?? null,
        participants: [],
        lastMessage: "No messages yet",
        last_message_at: now,
        unreadCount: 0,
      }

      setConversations((prev) => mergeNewConversation(prev, newConversation))
    }

    setShowDMModal(false)
    setDmSelectedUsers([])
    setDmSearchQuery("")
    setDmResults([])
    setCreatingDM(false)
    const other =
      dmSelectedUsers[0] ?? allUsers.find((u) => u.id === selectedDmUserId)
    const normalized = normalizeProfileUsername(other?.username ?? "")
    router.push(
      normalized
        ? buildDmThreadPath(normalized)
        : groupThreadPath(conversationId)
    )
  }

  const filteredConversations = useMemo(() => {
    const query = search.trim().toLowerCase()
    const list = query
      ? conversations.filter((c) =>
          (c.displayName || c.username).toLowerCase().includes(query)
        )
      : conversations

    return list.map((c) => ({
      id: c.id,
      is_group: c.is_group === true,
      is_pinned: c.is_pinned === true,
      name: c.name ?? null,
      displayName: c.displayName,
      username: c.username,
      profileUserId: c.profileUserId ?? null,
      lastMessage: c.lastMessage,
      lastMessageAt: c.last_message_at ?? null,
      avatar_url: c.avatar_url ?? null,
      unreadCount: c.unreadCount ?? 0,
    }))
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
              conversations.length === 0 ? (
                <EmptyState
                  title="No Conversations Yet"
                  description="Start chatting with traders in the community."
                  action={
                    <Link
                      href="/explore"
                      className="text-sm font-medium text-blue-300 hover:text-blue-200"
                    >
                      Explore Traders →
                    </Link>
                  }
                  className="py-10"
                />
              ) : (
                <EmptyState
                  title="No Conversations Found"
                  description="Try adjusting your search."
                  className="py-10"
                />
              )
            ) : (
              <MessagesConversationList
                conversations={filteredConversations}
                openConvoMenuId={openConvoMenuId}
                onOpen={handleOpenConversation}
                onToggleMenu={handleToggleConvoMenu}
                onPin={handlePinConversation}
                onMarkUnread={handleMarkConversationUnread}
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