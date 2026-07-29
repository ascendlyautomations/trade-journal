"use client"

import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from "react"
import Link from "next/link"
import { supabase } from "../../../lib/supabaseClient"
import NativeIosPullToRefresh from "@/app/components/NativeIosPullToRefresh"
import {
  isConversationParticipant,
  newConversationId,
} from "../../../lib/conversationAccess"
import { ensureDmConversation } from "@/lib/dmConversation"
import { devLog } from "@/lib/devLog"
import { buildDmThreadPath, groupThreadPath } from "@/lib/messageRoutes"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import { normalizeProfileUsername } from "@/lib/profileUsername"
import { markConversationMessagesSeen } from "@/lib/conversationReadMarking"
import {
  dispatchUnreadMessagesRefresh,
  fetchUnreadCountForConversation as fetchUnreadCountForConversationShared,
  fetchUnreadCountsForConversations,
  markConversationUnread,
} from "../../../lib/messageUnread"
import { fetchMutedConversationIds } from "@/lib/conversationMemberPreferences"
import {
  applyInboxPatchesToConversations,
  CONVERSATION_UPDATED_EVENT,
  INBOX_PATCHES_STORAGE_KEY,
  mergeConversationInboxFields,
  readInboxPatches,
} from "@/lib/conversationInboxSync"
import { markConversationOpenFromInbox } from "@/lib/conversationOpenIntent"
import { useRouter } from "next/navigation"
import MessagesConversationList from "../../components/messages/MessagesConversationList"
import EmptyState from "../../components/ui/EmptyState"
import {
  ConfirmModal,
  useDeleteChatConfirmation,
} from "../../components/ui"
import { SkeletonMessagesConversationList } from "../../components/ui/skeletons"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { DELETED_USER_LABEL, isDirectConversationPeerDeleted } from "@/lib/deletedUserDisplay"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import {
  fetchDemoConversations,
  fetchDemoDmSearchUsers,
} from "@/lib/demo/demoMessages"
import { isDemoUserId } from "@/lib/demo/constants"
import { isDemoSupabaseBlocked } from "@/lib/demo/demoSupabaseGuard"
import {
  readMessagesInboxSession,
  writeMessagesInboxSession,
} from "@/lib/messagesInboxSessionCache"
import {
  consumeMessagesInboxScrollY,
  saveMessagesInboxScrollY,
} from "@/lib/messagesInboxScroll"
import { isNativeIos } from "@/lib/nativePlatform"
import {
  fetchUserDmConversations,
  type DmConversationRow,
} from "@/lib/shareToConversations"
import { traceMessagesInbox } from "@/lib/messagesInboxTrace"

function mapDmRowToInboxConversation(
  conv: DmConversationRow,
  userId: string,
  unreadCount: number
) {
  const participants = conv.participants.map((p) => ({
    conversation_id: conv.id,
    user_id: p.user_id,
    profiles: p.profiles,
  }))

  const otherUser = conv.participants.find((p) => p.user_id !== userId)
  const profile = otherUser?.profiles ?? null

  const isGroup = conv.is_group
  const hasHistory = Boolean(conv.last_message?.trim())
  const peerDeleted = isDirectConversationPeerDeleted(
    isGroup,
    profile?.username,
    hasHistory
  )
  const peerLabel = peerDeleted ? DELETED_USER_LABEL : profile?.username || "user"
  const displayName = isGroup ? conv.name || "Group Chat" : peerLabel

  return {
    id: conv.id,
    is_group: isGroup,
    is_pinned: conv.is_pinned,
    name: conv.name || null,
    displayName,
    username: peerLabel,
    otherUserId: isGroup
      ? null
      : peerDeleted
        ? null
        : (profile?.id ?? otherUser?.user_id ?? null),
    profileUserId: isGroup
      ? null
      : peerDeleted
        ? null
        : (profile?.id ?? otherUser?.user_id ?? null),
    avatar_url: isGroup ? conv.avatar_url ?? null : profile?.avatar_url ?? null,
    participants,
    lastMessage: conv.last_message || "No messages yet",
    last_message_at: conv.last_message_at || null,
    unreadCount,
  }
}

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
  const { user: authUser, loading: profileLoading } = useUserProfile()
  const [conversations, setConversations] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [inboxLoadError, setInboxLoadError] = useState<string | null>(null)
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
  const user = authUser
  const inboxScrollRef = useRef<HTMLDivElement | null>(null)
  const pendingInboxScrollRef = useRef<number | null>(null)

  useLayoutEffect(() => {
    if (!isNativeIos()) return
    pendingInboxScrollRef.current = consumeMessagesInboxScrollY()
  }, [])

  useLayoutEffect(() => {
    if (!isNativeIos()) return
    const y = pendingInboxScrollRef.current
    if (y == null || loading) return
    const el = inboxScrollRef.current
    if (!el) return
    el.scrollTop = y
    pendingInboxScrollRef.current = null
  }, [loading, conversations.length])

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
      if (isDemoUserId(user.id)) {
        setGroupResults(fetchDemoDmSearchUsers(query, user.id))
        return
      }
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
      if (isDemoUserId(user.id)) {
        setGroupResults(fetchDemoDmSearchUsers(query, user.id))
        return
      }
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
    if (isDemoUserId(currentUserId)) {
      setAllUsers(fetchDemoDmSearchUsers("", currentUserId))
      return
    }
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

  const markMessageNotificationsRead = useCallback(
    async (currentUserId: string, reason: "page-open" | "chat-open") => {
      if (isDemoSupabaseBlocked()) return

      devLog("[messages] mark read start", {
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

      devLog("[messages] mark read success", {
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
      if (isDemoSupabaseBlocked()) return
      await markConversationMessagesSeen(currentUserId, conversationId)
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

  const fetchConversations = useCallback(async (userId: string, source = "unknown") => {
    traceMessagesInbox("fetch:start", { userId, source })

    if (isDemoUserId(userId)) {
      const sorted = fetchDemoConversations(userId)
      traceMessagesInbox("fetch:demo-result", {
        userId,
        source,
        conversationsLength: sorted.length,
      })
      setConversations(sorted)
      writeMessagesInboxSession(userId, sorted)
      return sorted
    }

    const { rows, error } = await fetchUserDmConversations(supabase, userId)

    traceMessagesInbox("step:2-conversations", {
      source,
      error: error?.message ?? null,
      rowCount: rows.length,
      firstRow: rows[0] ?? null,
    })

    if (error) {
      traceMessagesInbox("step:2-conversations:failed", {
        source,
        reason: "supabase_error",
        message: error.message,
      })
      setInboxLoadError("Couldn't load conversations. Please try again.")
      return null
    }

    if (rows.length === 0) {
      traceMessagesInbox("step:2-conversations:failed", {
        source,
        reason: "zero_rows",
      })
      setInboxLoadError(null)
      setConversations([])
      writeMessagesInboxSession(userId, [])
      return []
    }

    const convoIds = rows.map((c) => c.id)
    const [cursorCounts, mutedIds] = await Promise.all([
      fetchUnreadCountsForConversations(userId, convoIds),
      fetchMutedConversationIds(userId, convoIds),
    ])

    traceMessagesInbox("step:3-unread", {
      source,
      unreadConversationCount: Object.values(cursorCounts).filter(
        (count) => count > 0
      ).length,
      mutedConversationCount: mutedIds.size,
    })

    const unreadByConvo: Record<string, number> = {}
    for (const cid of convoIds) {
      unreadByConvo[cid] = mutedIds.has(cid) ? 0 : cursorCounts[cid] ?? 0
    }

    const convoData = rows.map((conv) =>
      mapDmRowToInboxConversation(conv, userId, unreadByConvo[conv.id] ?? 0)
    )

    const firstMapped = convoData[0]
    traceMessagesInbox("step:4-last-message", {
      source,
      conversationId: firstMapped?.id ?? null,
      lastMessageExists: Boolean(
        firstMapped?.lastMessage &&
          firstMapped.lastMessage !== "No messages yet"
      ),
      lastMessage: firstMapped?.lastMessage ?? null,
    })

    const sorted = sortConversationsDesc(
      applyInboxPatchesToConversations(convoData)
    )

    traceMessagesInbox("step:5-before-setState", {
      source,
      conversationsLength: sorted.length,
      firstConversationId: sorted[0]?.id ?? null,
    })

    setConversations(sorted)
    setInboxLoadError(null)
    writeMessagesInboxSession(userId, sorted)
    return sorted
  }, [])

  useEffect(() => {
    traceMessagesInbox("effect:load", {
      profileLoading,
      authUserId: authUser?.id ?? null,
      demoMode: isDemoModeActive(),
    })

    if (!authUser?.id) {
      if (!profileLoading && !isDemoModeActive()) {
        router.push("/login")
      }
      return
    }

    const userId = authUser.id

    const cached = readMessagesInboxSession(userId)
    traceMessagesInbox("cache:read", {
      userId,
      cachedLength: cached?.conversations.length ?? 0,
    })

    if (cached) {
      setConversations(cached.conversations)
      setLoading(false)
    }

    void fetchConversations(userId, "initial-load").finally(() => setLoading(false))
  }, [authUser?.id, profileLoading, fetchConversations, router])

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
      void fetchConversations(uid, "refresh")
    }

    const onWindowFocus = () => refresh()

    const onVisibilityChange = () => {
      if (document.visibilityState === "visible") {
        refresh()
      }
    }

    window.addEventListener("focus", onWindowFocus)
    document.addEventListener("visibilitychange", onVisibilityChange)

    return () => {
      window.removeEventListener("focus", onWindowFocus)
      document.removeEventListener("visibilitychange", onVisibilityChange)
    }
  }, [user?.id, fetchConversations])

  const openConversation = useCallback(
    (conversationId: string) => {
      void import("@/lib/nativeHaptics").then(({ hapticLight }) => {
        hapticLight("open-messages")
      })
      const item = conversations.find((c) => c.id === conversationId)
      let path = groupThreadPath(conversationId)
      let urlSegment = conversationId
      if (item && !item.is_group) {
        const normalized = normalizeProfileUsername(item.username ?? "")
        urlSegment =
          normalized && item.username !== "user"
            ? normalized
            : conversationId
        path =
          normalized && item.username !== "user"
            ? buildDmThreadPath(normalized)
            : groupThreadPath(conversationId)
      }

      setConversations((prev) =>
        prev.map((c) =>
          c.id === conversationId ? { ...c, unreadCount: 0 } : c
        )
      )

      markConversationOpenFromInbox(conversationId, urlSegment)
      if (isNativeIos()) {
        saveMessagesInboxScrollY(inboxScrollRef.current?.scrollTop ?? 0)
      }
      router.push(path)

      if (!user?.id) return

      const userId = user.id
      void (async () => {
        await markConversationRead(userId, conversationId)
        await markMessageNotificationsRead(userId, "chat-open")
        const list = await fetchConversations(userId)
        if (list) {
          setConversations(list)
        }
      })()
    },
    [
      user,
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

  const { requestDelete: requestDeleteConversation, confirmModalProps: deleteChatConfirmProps } =
    useDeleteChatConfirmation(handleDeleteConversation)

  const handleRequestDeleteConversation = useCallback(
    (conversationId: string) => {
      setOpenConvoMenuId(null)
      requestDeleteConversation(conversationId)
    },
    [requestDeleteConversation]
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
    [user, fetchConversations]
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
    [user, fetchUnreadCountForConversation]
  )

  async function createGroupChat() {
    if (isDemoModeActive()) {
      requestDemoSignup("default")
      return
    }
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

    if (isDemoModeActive()) {
      const username = dmSelectedUsers[0]?.username
      if (username) {
        router.push(buildDmThreadPath(username))
        setShowDMModal(false)
      } else {
        requestDemoSignup("default")
      }
      return
    }

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

  const showSkeleton =
    !authUser?.id || (loading && conversations.length === 0)
  const showEmptyNoConversations =
    !showSkeleton &&
    !inboxLoadError &&
    filteredConversations.length === 0 &&
    conversations.length === 0
  const showInboxLoadError =
    !showSkeleton && !!inboxLoadError && conversations.length === 0
  const showEmptySearch =
    !showSkeleton &&
    filteredConversations.length === 0 &&
    conversations.length > 0

  useEffect(() => {
    traceMessagesInbox("step:6-after-render", {
      authUserId: authUser?.id ?? null,
      profileLoading,
      loading,
      conversationsLength: conversations.length,
      filteredConversationsLength: filteredConversations.length,
      search: search.trim(),
      showSkeleton,
      showEmptyNoConversations,
      showEmptySearch,
    })
  }, [
    authUser?.id,
    profileLoading,
    loading,
    conversations.length,
    filteredConversations.length,
    search,
    showSkeleton,
    showEmptyNoConversations,
    showEmptySearch,
  ])

  console.log("INBOX_RENDER_COMPONENT", {
    conversationsLength: conversations.length,
    filteredLength: filteredConversations.length,
    loading,
    showSkeleton,
    showEmptyNoConversations,
    showEmptySearch,
  })

  return (
    <>
      <div
        data-tt-native-surface="messages"
        data-tt-messages-inbox
        className="flex h-[var(--app-viewport-height)] min-h-0 flex-col overflow-hidden bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white px-6 pb-6 pt-0"
      >

        <div className="mx-auto flex h-full min-h-0 w-full max-w-3xl flex-col">

          <input
            data-tt-messages-inbox-search
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search conversations..."
            className="mt-4 mb-3 w-full shrink-0 rounded border border-white/10 bg-black p-3 focus:border-emerald-400 focus:outline-none"
          />

          <div
            data-tt-messages-inbox-actions
            className="mb-4 flex shrink-0 justify-start gap-2"
          >
            <button
              type="button"
              onClick={openDMModal}
              className="min-h-9 w-auto rounded-lg bg-blue-500 px-2.5 py-1.5 text-sm text-white hover:bg-blue-600"
            >
              New Chat
            </button>
            <button
              type="button"
              onClick={() => setShowGroupModal(true)}
              className="min-h-9 w-auto rounded-lg bg-blue-500 px-2.5 py-1.5 text-sm text-white hover:bg-blue-600"
            >
              New Group
            </button>
          </div>

          <NativeIosPullToRefresh
            scrollRef={inboxScrollRef}
            className="min-h-0 flex-1 overflow-y-auto"
            onRefresh={async () => {
              if (!authUser?.id) return
              await fetchConversations(authUser.id, "pull-to-refresh")
            }}
          >
            {showSkeleton ? (
              <SkeletonMessagesConversationList />
            ) : showInboxLoadError ? (
              <EmptyState
                title="Couldn't Load Conversations"
                description={inboxLoadError}
                className="py-10"
                action={
                  authUser?.id ? (
                    <button
                      type="button"
                      onClick={() => {
                        setLoading(true)
                        setInboxLoadError(null)
                        void fetchConversations(authUser.id, "retry").finally(
                          () => setLoading(false)
                        )
                      }}
                      className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600"
                    >
                      Retry
                    </button>
                  ) : undefined
                }
              />
            ) : showEmptyNoConversations ? (
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
            ) : showEmptySearch ? (
              <EmptyState
                title="No Conversations Found"
                description="Try adjusting your search."
                className="py-10"
              />
            ) : (
              <MessagesConversationList
                conversations={filteredConversations}
                openConvoMenuId={openConvoMenuId}
                onOpen={handleOpenConversation}
                onToggleMenu={handleToggleConvoMenu}
                onPin={handlePinConversation}
                onMarkUnread={handleMarkConversationUnread}
                onDelete={handleRequestDeleteConversation}
              />
            )}
          </NativeIosPullToRefresh>

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
                    <ProfileAvatarImg
                      src={u.avatar_url}
                      className="h-8 w-8 shrink-0 transition hover:scale-105"
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
                    <ProfileAvatarImg
                      src={u.avatar_url}
                      className="h-8 w-8 shrink-0 transition hover:scale-105"
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

      <ConfirmModal {...deleteChatConfirmProps} />
    </>
  )
}