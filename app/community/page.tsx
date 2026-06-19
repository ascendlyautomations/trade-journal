"use client"

import {
  Suspense,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ChangeEvent,
} from "react"
import { useRouter, useSearchParams } from "next/navigation"
import Navbar from "../components/Navbar"
import EmptyState from "../components/ui/EmptyState"
import {
  SkeletonCommunityPage,
  SkeletonLeaderboardRow,
  SkeletonMessage,
} from "../components/ui/skeletons"
import DmStyleComposer from "../components/DmStyleComposer"
import { supabase } from "../../lib/supabaseClient"
import { compressImage } from "@/lib/compressImage"
import { formatEST } from "@/lib/formatEST"
import { isUserPro, reachedMessagesCommentsLimit } from "@/lib/freePlanLimits"
import { feedbackPresets, persistentError } from "@/lib/feedbackPresets"
import { formatMoneyUnknown, formatRR } from "@/lib/formatDisplay"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import { createRoomJoinNotification } from "@/lib/createRoomJoinNotification"
import { notifyGettingStartedChecklistMaybeCompleted } from "@/lib/gettingStartedProgressSync"
import { isCurrentUserAdmin } from "@/lib/adminUsers"
import { isBetaAnnouncementsSection } from "@/lib/betaHub"
import { isProfileUuidSegment } from "@/lib/profileRoutes"
import { canEditRoomMessage } from "@/lib/roomModeration"
import RoomMessageActionsMenu from "../components/RoomMessageActionsMenu"
import {
  ProfileAvatarLink,
  ProfileUsernameLink,
} from "../components/ProfileLink"

type Room = {
  id: string
  name?: string | null
  description?: string | null
  slug?: string | null
  image_url?: string | null
  /** If present from API joins, used as sidebar avatar fallback after image_url */
  avatar_url?: string | null
  owner_user_id?: string | null
  show_on_profile?: boolean | null
}

type RoomMessage = {
  id: string
  room_id: string
  user_id: string
  /** JSON array of user ids who have read this message (same pattern as `messages.seen_by`) */
  seen_by?: unknown
  pinned?: boolean | null
  section_id?: string | null
  type?: string | null
  trade_id?: string | null
  content: string
  image_url?: string | null
  created_at: string
  trades?: {
    id?: string
    ticker?: string | null
    image_url?: string | null
    pnl?: number | string | null
    rr?: number | string | null
  } | null
  profiles?: {
    username?: string | null
    avatar_url?: string | null
  } | null
}

type ActivePresence = {
  user_id: string
  profiles?: {
    id?: string
    username?: string | null
    avatar_url?: string | null
  } | null
}

type RoomMemberManage = {
  user_id: string
  profiles?: {
    id?: string
    username?: string | null
    name?: string | null
    avatar_url?: string | null
  } | null
}

type RoomBanManage = {
  id: string
  user_id: string
  profiles?: {
    id?: string
    username?: string | null
    name?: string | null
    avatar_url?: string | null
  } | null
}

type MemberActionConfirm =
  | { kind: "remove"; userId: string }
  | { kind: "ban"; userId: string }
  | { kind: "unban"; banId: string }

type DeleteSectionConfirm = {
  sectionId: string
  sectionName: string
  messageCount: number
}

function ActionSpinner({ className = "border-current" }: { className?: string }) {
  return (
    <span
      className={`inline-block h-3 w-3 shrink-0 animate-spin rounded-full border-2 border-t-transparent ${className}`}
      aria-hidden
    />
  )
}

function tradeImageSrc(imageUrl: string | null | undefined): string | null {
  const raw = imageUrl != null ? String(imageUrl).trim() : ""
  if (!raw) return null
  if (raw.startsWith("http")) return raw
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return null
  return `${base}/storage/v1/object/public/screenshots/${raw}`
}

function normalizeRoomMessageSeenBy(raw: unknown): string[] {
  if (!Array.isArray(raw)) return []
  return raw.map((x) => String(x)).filter(Boolean)
}

function roomMessageIsUnreadForUser(
  msg: { user_id: string; seen_by?: unknown },
  userId: string
): boolean {
  if (msg.user_id === userId) return false
  const seen = normalizeRoomMessageSeenBy(msg.seen_by)
  return !seen.includes(userId)
}

/** Per-room unread: true if any message from others lacks current user in seen_by. */
async function fetchUnreadByRoomIds(
  roomIds: string[],
  userId: string
): Promise<Record<string, boolean>> {
  const unread: Record<string, boolean> = {}
  if (roomIds.length === 0) return unread

  const { data, error } = await supabase
    .from("room_messages")
    .select("room_id, user_id, seen_by")
    .in("room_id", roomIds)
    .neq("user_id", userId)

  if (error) {
    console.error("fetchUnreadByRoomIds:", error)
    return unread
  }

  for (const row of data ?? []) {
    if (roomMessageIsUnreadForUser(row, userId)) {
      unread[String(row.room_id)] = true
    }
  }
  return unread
}

async function markAllRoomMessagesSeenForUser(roomId: string, userId: string) {
  const { data, error } = await supabase
    .from("room_messages")
    .select("id, user_id, seen_by")
    .eq("room_id", roomId)
    .neq("user_id", userId)

  if (error) {
    console.error("markAllRoomMessagesSeenForUser read:", error)
    return
  }

  const pending = (data ?? []).filter(
    (row) => !normalizeRoomMessageSeenBy(row.seen_by).includes(userId)
  )

  await Promise.all(
    pending.map((row) => {
      const next = [...normalizeRoomMessageSeenBy(row.seen_by), userId]
      return supabase.from("room_messages").update({ seen_by: next }).eq("id", row.id)
    })
  )
}

/** Cache key: room + active section + section id layout (so channel / section changes miss cache correctly). */
function buildRoomMessagesCacheKey(
  roomId: string,
  sectionsList: { id: string; name?: string | null }[],
  activeSectionId: string | null
): string {
  const sectionSig = sectionsList.map((s) => String(s.id)).join(",")
  return `${roomId}::${activeSectionId ?? "null"}::${sectionSig}`
}

async function appendSelfToSeenByForRoomMessage(
  messageId: string,
  userId: string
) {
  const { data, error } = await supabase
    .from("room_messages")
    .select("seen_by, user_id")
    .eq("id", messageId)
    .maybeSingle()

  if (error || !data || data.user_id === userId) return

  const seen = normalizeRoomMessageSeenBy(data.seen_by)
  if (seen.includes(userId)) return

  await supabase
    .from("room_messages")
    .update({ seen_by: [...seen, userId] })
    .eq("id", messageId)
}

function CommunityContent() {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const router = useRouter()
  const searchParams = useSearchParams()
  const roomParam = searchParams.get("room")
  const setupMode = searchParams.get("setup") === "true"
  const [user, setUser] = useState<any>(null)
  const [username, setUsername] = useState("User")
  const [rooms, setRooms] = useState<Room[]>([])
  const [selectedRoomId, setSelectedRoomId] = useState<string | null>(null)
  const [messages, setMessages] = useState<RoomMessage[]>([])
  const [pinnedMessages, setPinnedMessages] = useState<RoomMessage[]>([])
  const [messagesByRoom, setMessagesByRoom] = useState<
    Record<string, { pinned: RoomMessage[]; main: RoomMessage[] }>
  >({})
  const [loadingRooms, setLoadingRooms] = useState(true)
  const [loadingMessages, setLoadingMessages] = useState(false)
  const [draft, setDraft] = useState("")
  const [activeUsers, setActiveUsers] = useState<ActivePresence[]>([])
  const [typingUsers, setTypingUsers] = useState<string[]>([])
  const [selectTrade, setSelectTrade] = useState(false)
  const [userTrades, setUserTrades] = useState<any[]>([])
  const [mobileRoomsOpen, setMobileRoomsOpen] = useState(false)
  const [sections, setSections] = useState<any[]>([])
  const [selectedSectionId, setSelectedSectionId] = useState<string | null>(null)
  const [isOwner, setIsOwner] = useState(false)
  const [isAdmin, setIsAdmin] = useState(false)
  const [activeMembers, setActiveMembers] = useState<number>(0)
  const [leftMembers, setLeftMembers] = useState<number>(0)
  const [showOnProfile, setShowOnProfile] = useState(true)
  const [roomName, setRoomName] = useState("")
  const [inviteOrigin, setInviteOrigin] = useState("")
  const [roomImage, setRoomImage] = useState<string | null>(null)
  const [inviteTargetRoom, setInviteTargetRoom] = useState<Room | null>(null)
  const [showRoomSettings, setShowRoomSettings] = useState(false)
  const [showManageMembers, setShowManageMembers] = useState(false)
  const [memberSearchQuery, setMemberSearchQuery] = useState("")
  const [manageMembers, setManageMembers] = useState<RoomMemberManage[]>([])
  const [bannedUsers, setBannedUsers] = useState<RoomBanManage[]>([])
  const [loadingManageMembers, setLoadingManageMembers] = useState(false)
  const [removingMemberId, setRemovingMemberId] = useState<string | null>(null)
  const [banningMemberId, setBanningMemberId] = useState<string | null>(null)
  const [unbanningBanId, setUnbanningBanId] = useState<string | null>(null)
  const [memberActionConfirm, setMemberActionConfirm] =
    useState<MemberActionConfirm | null>(null)
  const [deleteSectionConfirm, setDeleteSectionConfirm] =
    useState<DeleteSectionConfirm | null>(null)
  const [deletingSectionId, setDeletingSectionId] = useState<string | null>(null)
  const [activeMessageMenuId, setActiveMessageMenuId] = useState<string | null>(
    null
  )
  const [editingMessageId, setEditingMessageId] = useState<string | null>(null)
  const [editingMessageContent, setEditingMessageContent] = useState("")
  const [deletingMessageId, setDeletingMessageId] = useState<string | null>(
    null
  )
  const [joiningRoomId, setJoiningRoomId] = useState<string | null>(null)
  const [sendingMessage, setSendingMessage] = useState(false)
  const sendingMessageRef = useRef(false)
  const [showInviteModal, setShowInviteModal] = useState(false)
  /** room id → has at least one unread message (others’ messages not in seen_by) */
  const [unreadByRoomId, setUnreadByRoomId] = useState<Record<string, boolean>>(
    {}
  )
  const [showCreateSectionModal, setShowCreateSectionModal] = useState(false)
  const [newSectionName, setNewSectionName] = useState("")
  const [newSectionAllowChat, setNewSectionAllowChat] = useState(true)
  const [editingSection, setEditingSection] = useState<any>(null)
  const [editSectionName, setEditSectionName] = useState("")
  const [editAllowChat, setEditAllowChat] = useState(true)
  const typingChannelRef = useRef<any>(null)
  const messagesScrollRef = useRef<HTMLDivElement | null>(null)
  const sectionFilterRef = useRef<{ len: number; id: string | null }>({
    len: 0,
    id: null,
  })
  const sectionsRef = useRef(sections)
  const roomIdsForUnreadRef = useRef<string[]>([])
  const messagesByRoomRef = useRef<
    Record<string, { pinned: RoomMessage[]; main: RoomMessage[] }>
  >({})
  const roomMessagesFetchGenRef = useRef(0)

  messagesByRoomRef.current = messagesByRoom

  const selectedRoom = useMemo(
    () => rooms.find((r) => r.id === selectedRoomId) ?? null,
    [rooms, selectedRoomId]
  )

  /** Owner’s room(s) first; does not change fetch order in state, only sidebar display. */
  const sortedSidebarRooms = useMemo(() => {
    const uid = user?.id
    if (!uid || rooms.length === 0) return rooms
    const ownedRooms = rooms.filter((r) => r.owner_user_id === uid)
    const otherRooms = rooms.filter((r) => r.owner_user_id !== uid)
    if (ownedRooms.length === 0) return rooms
    return [...ownedRooms, ...otherRooms]
  }, [rooms, user?.id])

  const needsJoin = useMemo(() => {
    if (!inviteTargetRoom || !selectedRoomId) return false
    return (
      inviteTargetRoom.id === selectedRoomId &&
      !rooms.some((r) => r.id === selectedRoomId)
    )
  }, [inviteTargetRoom, selectedRoomId, rooms])

  const filteredManageMembers = useMemo(() => {
    const q = memberSearchQuery.trim().toLowerCase()
    if (!q) return manageMembers
    return manageMembers.filter((m) => {
      const username = String(m.profiles?.username ?? "").toLowerCase()
      const name = String(m.profiles?.name ?? "").toLowerCase()
      return username.includes(q) || name.includes(q)
    })
  }, [manageMembers, memberSearchQuery])

  const filteredBannedUsers = useMemo(() => {
    const q = memberSearchQuery.trim().toLowerCase()
    if (!q) return bannedUsers
    return bannedUsers.filter((b) => {
      const username = String(b.profiles?.username ?? "").toLowerCase()
      const name = String(b.profiles?.name ?? "").toLowerCase()
      return username.includes(q) || name.includes(q)
    })
  }, [bannedUsers, memberSearchQuery])

  const memberActionBusy =
    removingMemberId !== null ||
    banningMemberId !== null ||
    unbanningBanId !== null

  const userIdRef = useRef<string | null>(null)
  const needsJoinRef = useRef(false)
  const usernameRef = useRef("")
  userIdRef.current = user?.id ?? null
  needsJoinRef.current = needsJoin
  usernameRef.current = username

  useEffect(() => {
    roomIdsForUnreadRef.current = rooms.map((r) => r.id)
  }, [rooms])

  useEffect(() => {
    if (!user?.id || rooms.length === 0) {
      setUnreadByRoomId({})
      return
    }
    const roomIds = rooms.map((r) => r.id)
    let cancelled = false
    void (async () => {
      const next = await fetchUnreadByRoomIds(roomIds, user.id)
      if (!cancelled) setUnreadByRoomId(next)
    })()
    return () => {
      cancelled = true
    }
  }, [rooms, user?.id])

  useEffect(() => {
    if (!selectedRoomId || !user?.id || needsJoin || loadingMessages) return
    const roomIds = roomIdsForUnreadRef.current
    let cancelled = false
    void (async () => {
      await markAllRoomMessagesSeenForUser(selectedRoomId, user.id)
      if (cancelled) return
      const next = await fetchUnreadByRoomIds(roomIds, user.id)
      if (!cancelled) setUnreadByRoomId(next)
    })()
    return () => {
      cancelled = true
    }
  }, [selectedRoomId, user?.id, loadingMessages, needsJoin])

  useEffect(() => {
    if (!user?.id) return

    const refreshUnread = () => {
      const ids = roomIdsForUnreadRef.current
      if (ids.length === 0) return
      void (async () => {
        const next = await fetchUnreadByRoomIds(ids, user.id)
        setUnreadByRoomId(next)
      })()
    }

    const onVis = () => {
      if (document.visibilityState === "visible") refreshUnread()
    }

    document.addEventListener("visibilitychange", onVis)
    const intervalId = window.setInterval(refreshUnread, 45000)

    return () => {
      document.removeEventListener("visibilitychange", onVis)
      window.clearInterval(intervalId)
    }
  }, [user?.id])

  const inviteRoomKey = useMemo(() => {
    if (!selectedRoom) return ""
    const rawSlug = selectedRoom.slug
    if (rawSlug != null && String(rawSlug).trim() !== "")
      return String(rawSlug)
    return selectedRoom.id ? String(selectedRoom.id) : ""
  }, [selectedRoom])

  const inviteLinkDisplay = useMemo(() => {
    if (!inviteOrigin || !inviteRoomKey) return ""
    return `${inviteOrigin}/trade-rooms?room=${encodeURIComponent(inviteRoomKey)}`
  }, [inviteOrigin, inviteRoomKey])
  const inviteLink =
    typeof window !== "undefined"
      ? `${window.location.origin}/trade-rooms?room=${selectedRoom?.slug ?? ""}`
      : ""

  const currentSection = useMemo(
    () => sections.find((s) => s.id === selectedSectionId) ?? null,
    [sections, selectedSectionId]
  )

  const isBetaAnnouncementsLocked = useMemo(
    () => isBetaAnnouncementsSection(selectedRoom?.slug, currentSection),
    [selectedRoom?.slug, currentSection]
  )

  const canPostInRoom = useMemo(() => {
    if (!selectedRoomId || needsJoin) return false
    if (isOwner) return true
    if (isBetaAnnouncementsLocked) return isAdmin
    if (sections.length === 0) return true
    return currentSection?.allow_members_chat !== false
  }, [
    selectedRoomId,
    needsJoin,
    isOwner,
    isAdmin,
    isBetaAnnouncementsLocked,
    sections.length,
    currentSection?.allow_members_chat,
  ])

  useEffect(() => {
    setInviteOrigin(typeof window !== "undefined" ? window.location.origin : "")
  }, [])

  useEffect(() => {
    setRoomName(selectedRoom?.name ?? "")
  }, [selectedRoom?.name, selectedRoom?.id])

  useEffect(() => {
    setShowOnProfile(selectedRoom?.show_on_profile ?? true)
  }, [selectedRoom?.show_on_profile, selectedRoom?.id])

  useEffect(() => {
    const url = selectedRoom?.image_url
    setRoomImage(
      url != null && String(url).trim() !== "" ? String(url) : null
    )
  }, [selectedRoom?.image_url, selectedRoom?.id])

  useEffect(() => {
    sectionsRef.current = sections
  }, [sections])

  useEffect(() => {
    sectionFilterRef.current = {
      len: sections.length,
      id: selectedSectionId,
    }
  }, [sections.length, selectedSectionId])

  useEffect(() => {
    if (!user?.id) {
      setIsAdmin(false)
      return
    }
    void isCurrentUserAdmin().then(setIsAdmin)
  }, [user?.id])

  useEffect(() => {
    async function checkOwner() {
      if (!selectedRoomId) {
        setIsOwner(false)
        return
      }

      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (!user) {
        setIsOwner(false)
        return
      }

      const { data } = await supabase
        .from("rooms")
        .select("owner_user_id")
        .eq("id", selectedRoomId)
        .maybeSingle()

      setIsOwner(data?.owner_user_id === user.id)
    }

    void checkOwner()
  }, [selectedRoomId])

  useEffect(() => {
    setActiveMessageMenuId(null)
    setEditingMessageId(null)
    setEditingMessageContent("")
  }, [selectedRoomId, selectedSectionId])

  useEffect(() => {
    if (!selectedRoomId) {
      setActiveMembers(0)
      setLeftMembers(0)
      return
    }

    void loadMemberStats(selectedRoomId)
  }, [selectedRoomId])

  useEffect(() => {
    if (!showManageMembers || !selectedRoomId || !isOwner) return
    void loadManageMembers(selectedRoomId)
  }, [showManageMembers, selectedRoomId, isOwner])

  function applySectionFiltersToQuery(
    q: any,
    roomId: string,
    sectionsList: { id: string; name?: string | null }[],
    activeSectionId: string | null
  ) {
    let next = q.eq("room_id", roomId)

    if (sectionsList.length > 0) {
      if (activeSectionId) {
        const sec = sectionsList.find((s) => s.id === activeSectionId)
        const nameLower = String(sec?.name ?? "")
          .trim()
          .toLowerCase()
        if (nameLower === "general") {
          next = next.or(
            `section_id.eq.${activeSectionId},section_id.is.null`
          )
        } else {
          next = next.eq("section_id", activeSectionId)
        }
      } else {
        next = next.is("section_id", null)
      }
    }

    return next
  }

  function sectionMessageFilter(
    q: any,
    roomId: string,
    sectionId: string,
    sectionName?: string | null
  ) {
    let next = q.eq("room_id", roomId)
    const nameLower = String(sectionName ?? "")
      .trim()
      .toLowerCase()
    if (nameLower === "general") {
      next = next.or(`section_id.eq.${sectionId},section_id.is.null`)
    } else {
      next = next.eq("section_id", sectionId)
    }
    return next
  }

  async function countSectionMessages(
    roomId: string,
    sectionId: string,
    sectionName?: string | null
  ) {
    let q = supabase
      .from("room_messages")
      .select("*", { count: "exact", head: true })
    q = sectionMessageFilter(q, roomId, sectionId, sectionName)
    const { count, error } = await q
    if (error) {
      console.error("countSectionMessages:", error)
      return { count: 0, error }
    }
    return { count: count ?? 0, error: null }
  }

  async function deleteSectionMessages(
    roomId: string,
    sectionId: string,
    sectionName?: string | null
  ) {
    let q = supabase.from("room_messages").delete()
    q = sectionMessageFilter(q, roomId, sectionId, sectionName)
    return q
  }

  async function fetchRoomMessages(
    roomId: string,
    sectionsList: { id: string; name?: string | null }[],
    activeSectionId: string | null,
    options?: { bypassCache?: boolean }
  ) {
    const cacheKey = buildRoomMessagesCacheKey(
      roomId,
      sectionsList,
      activeSectionId
    )

    const loadGen = ++roomMessagesFetchGenRef.current

    if (!options?.bypassCache) {
      const cached = messagesByRoomRef.current[cacheKey]
      if (cached) {
        if (loadGen !== roomMessagesFetchGenRef.current) return
        setPinnedMessages(cached.pinned)
        setMessages(cached.main)
        setLoadingMessages(false)
        return
      }
    }

    if (loadGen !== roomMessagesFetchGenRef.current) return

    setLoadingMessages(true)

    const selectShape = `
        *,
        trades (
          id,
          ticker,
          image_url,
          pnl,
          rr
        ),
        profiles (
          username,
          avatar_url
        )
      `

    let pinnedQ = supabase
      .from("room_messages")
      .select(selectShape)
      .eq("pinned", true)
      .order("created_at", { ascending: false })
      .limit(100)

    pinnedQ = applySectionFiltersToQuery(
      pinnedQ,
      roomId,
      sectionsList,
      activeSectionId
    )

    let mainQ = supabase
      .from("room_messages")
      .select(selectShape)
      .eq("pinned", false)
      .order("created_at", { ascending: false })
      .limit(100)

    mainQ = applySectionFiltersToQuery(
      mainQ,
      roomId,
      sectionsList,
      activeSectionId
    )

    const [pinnedRes, mainRes] = await Promise.all([pinnedQ, mainQ])

    if (loadGen !== roomMessagesFetchGenRef.current) {
      setLoadingMessages(false)
      return
    }

    if (pinnedRes.error) {
      console.error(
        "room_messages pinned fetch:",
        JSON.stringify(pinnedRes.error, null, 2)
      )
    }

    const pinnedData = pinnedRes.error
      ? []
      : (((pinnedRes.data || []) as RoomMessage[]).slice().reverse() as RoomMessage[])
    setPinnedMessages(pinnedData)

    if (mainRes.error) {
      console.error(
        "room_messages fetch FULL:",
        JSON.stringify(mainRes.error, null, 2)
      )
      setMessages([])
      setPinnedMessages([])
      setLoadingMessages(false)
      return
    }

    const mainData = ((mainRes.data || []) as RoomMessage[]).slice().reverse()
    setMessages(mainData)

    setMessagesByRoom((prev) => ({
      ...prev,
      [cacheKey]: { pinned: pinnedData, main: mainData },
    }))

    setLoadingMessages(false)
  }

  async function handleTogglePin(
    messageId: string,
    isPinned: boolean | null | undefined
  ) {
    const { error } = await supabase
      .from("room_messages")
      .update({ pinned: !isPinned })
      .eq("id", messageId)

    if (error) {
      console.error("handleTogglePin:", error)
      return
    }

    if (selectedRoomId) {
      await fetchRoomMessages(selectedRoomId, sections, selectedSectionId, {
        bypassCache: true,
      })
    }
  }

  function invalidateRoomMessagesCache() {
    if (!selectedRoomId) return
    const cacheKey = buildRoomMessagesCacheKey(
      selectedRoomId,
      sections,
      selectedSectionId
    )
    setMessagesByRoom((prev) => {
      if (!(cacheKey in prev)) return prev
      const next = { ...prev }
      delete next[cacheKey]
      return next
    })
  }

  function startEditMessage(msg: RoomMessage) {
    setActiveMessageMenuId(null)
    setEditingMessageId(msg.id)
    setEditingMessageContent(msg.content ?? "")
  }

  function cancelEditMessage() {
    setEditingMessageId(null)
    setEditingMessageContent("")
  }

  async function handleSaveEditMessage(messageId: string) {
    const trimmed = editingMessageContent.trim()
    if (!trimmed) return

    const { error } = await supabase
      .from("room_messages")
      .update({ content: trimmed })
      .eq("id", messageId)

    if (error) {
      console.error("handleSaveEditMessage:", error)
      return
    }

    const updater = (m: RoomMessage) =>
      m.id === messageId ? { ...m, content: trimmed } : m

    setMessages((prev) => prev.map(updater))
    setPinnedMessages((prev) => prev.map(updater))
    cancelEditMessage()
    invalidateRoomMessagesCache()
  }

  async function handleDeleteMessage(messageId: string) {
    setActiveMessageMenuId(null)
    setDeletingMessageId(messageId)

    const { error } = await supabase
      .from("room_messages")
      .delete()
      .eq("id", messageId)

    setDeletingMessageId(null)

    if (error) {
      console.error("handleDeleteMessage:", error)
      return
    }

    if (editingMessageId === messageId) {
      cancelEditMessage()
    }

    setMessages((prev) => prev.filter((m) => m.id !== messageId))
    setPinnedMessages((prev) => prev.filter((m) => m.id !== messageId))
    invalidateRoomMessagesCache()
  }

  async function loadSections(roomId: string) {
    const { data, error } = await supabase
      .from("room_sections")
      .select("*")
      .eq("room_id", roomId)
      .order("position", { ascending: true })

    if (error) {
      console.error(error)
    }

    const list = data || []
    setSections(list)

    if (list.length > 0) {
      setSelectedSectionId(list[0].id)
      return { list, activeSectionId: list[0].id as string }
    }

    setSelectedSectionId(null)
    return { list, activeSectionId: null as string | null }
  }

  async function refetchSections() {
    if (!selectedRoomId) return
    const { list, activeSectionId } = await loadSections(selectedRoomId)
    await fetchRoomMessages(selectedRoomId, list, activeSectionId, {
      bypassCache: true,
    })
  }

  async function handleAddSection() {
    if (sections.length >= 5) {
      showPopup({ type: "warning", message: "Max 5 pages allowed" })
      return
    }
    if (!selectedRoomId) return

    const nextPosition =
      sections.length > 0
        ? Math.max(...sections.map((s) => Number(s.position) || 0), 0) + 1
        : 1

    const { error } = await supabase.from("room_sections").insert({
      room_id: selectedRoomId,
      name: `Page ${sections.length + 1}`,
      position: nextPosition,
      allow_members_chat: true,
    })

    if (error) {
      console.error(error)
      return
    }

    await refetchSections()
  }

  async function executeDeleteSection(sectionId: string) {
    if (!selectedRoomId || sections.length <= 1) {
      showPopup({ type: "warning", message: "You must have at least 1 page" })
      return
    }

    const section = sections.find((s) => s.id === sectionId)
    if (!section) return

    setDeletingSectionId(sectionId)

    const { error: messagesError } = await deleteSectionMessages(
      selectedRoomId,
      sectionId,
      section.name
    )

    if (messagesError) {
      setDeletingSectionId(null)
      console.error("executeDeleteSection messages:", messagesError)
      showPopup(persistentError("Delete Failed", "Failed to delete channel messages"))
      return
    }

    const { error: sectionError } = await supabase
      .from("room_sections")
      .delete()
      .eq("id", sectionId)

    setDeletingSectionId(null)

    if (sectionError) {
      console.error("executeDeleteSection section:", sectionError)
      showPopup(persistentError("Delete Failed", "Failed to delete channel"))
      return
    }

    showPopup({ type: "success", message: "Channel deleted" })
    if (editingSection?.id === sectionId) {
      setEditingSection(null)
    }
    await refetchSections()
  }

  function openChannelSettings(section: {
    id: string
    name?: string | null
    allow_members_chat?: boolean
  }) {
    setEditingSection(section)
    setEditSectionName(section.name ?? "")
    setEditAllowChat(section.allow_members_chat !== false)
  }

  function requestDeleteFromChannelSettings() {
    if (!editingSection || deletingSectionId) return
    const sectionId = editingSection.id
    setEditingSection(null)
    void promptDeleteSection(sectionId)
  }

  async function promptDeleteSection(sectionId: string) {
    if (sections.length <= 1) {
      showPopup({ type: "warning", message: "You must have at least 1 page" })
      return
    }
    if (!selectedRoomId) return

    const section = sections.find((s) => s.id === sectionId)
    if (!section) return

    const { count, error } = await countSectionMessages(
      selectedRoomId,
      sectionId,
      section.name
    )

    if (error) {
      showPopup({ type: "error", message: "Failed to check channel messages" })
      return
    }

    if (count > 0) {
      setDeleteSectionConfirm({
        sectionId,
        sectionName: String(section.name ?? "Channel"),
        messageCount: count,
      })
      return
    }

    await executeDeleteSection(sectionId)
  }

  async function handleDeleteSectionConfirm() {
    if (!deleteSectionConfirm || deletingSectionId) return
    const { sectionId } = deleteSectionConfirm
    setDeleteSectionConfirm(null)
    await executeDeleteSection(sectionId)
  }

  async function handleCreateSection() {
    const trimmed = newSectionName.trim()
    if (!trimmed || !selectedRoomId) return

    if (sections.length >= 5) {
      showPopup({ type: "warning", message: "Max 5 pages allowed" })
      return
    }

    try {
      const { data: newSection, error } = await supabase
        .from("room_sections")
        .insert({
          room_id: selectedRoomId,
          name: trimmed,
          position: sections.length + 1,
          allow_members_chat: newSectionAllowChat,
        })
        .select()
        .single()

      if (error) throw error
      if (newSection) {
        setSections((prev) => [...prev, newSection])
      }

      setNewSectionName("")
      setNewSectionAllowChat(true)
      setShowCreateSectionModal(false)
    } catch (err) {
      console.error(err)
      showPopup({ type: "error", message: "Failed to create channel" })
    }
  }

  async function handleSaveSectionEdit() {
    if (!editingSection) return

    const trimmed = editSectionName.trim()
    if (!trimmed) {
      showPopup({ type: "error", message: "Channel name cannot be empty" })
      return
    }

    try {
      const { error } = await supabase
        .from("room_sections")
        .update({
          name: trimmed,
          allow_members_chat: editAllowChat,
        })
        .eq("id", editingSection.id)

      if (error) throw error

      setSections((prev) =>
        prev.map((s) =>
          s.id === editingSection.id
            ? {
                ...s,
                name: trimmed,
                allow_members_chat: editAllowChat,
              }
            : s
        )
      )

      setEditingSection(null)
      showPopup({ type: "success", message: "Channel saved" })
    } catch (err) {
      console.error(err)
      showPopup({ type: "error", message: "Failed to update channel" })
    }
  }

  async function handleRenameRoom(opts?: { closeSettings?: boolean }) {
    if (!selectedRoomId) return
    const trimmed = roomName.trim()

    try {
      const { error } = await supabase
        .from("rooms")
        .update({
          name: trimmed,
          show_on_profile: showOnProfile,
        })
        .eq("id", selectedRoomId)

      if (error) throw error

      setRooms((prev) =>
        prev.map((r) =>
          r.id === selectedRoomId
            ? { ...r, name: trimmed, show_on_profile: showOnProfile }
            : r
        )
      )
      if (opts?.closeSettings) setShowRoomSettings(false)
    } catch (err) {
      console.error(err)
    }
  }

  async function loadMemberStats(roomId: string) {
    const { count: active } = await supabase
      .from("room_members")
      .select("*", { count: "exact", head: true })
      .eq("room_id", roomId)
      .is("left_at", null)

    const { count: total } = await supabase
      .from("room_members")
      .select("*", { count: "exact", head: true })
      .eq("room_id", roomId)

    setActiveMembers(active || 0)
    setLeftMembers((total || 0) - (active || 0))
  }

  async function loadManageMembers(roomId: string) {
    setLoadingManageMembers(true)

    const [membersResult, bansResult] = await Promise.all([
      supabase
        .from("room_members")
        .select(
          `
          user_id,
          profiles (
            id,
            username,
            name,
            avatar_url
          )
        `
        )
        .eq("room_id", roomId)
        .is("left_at", null),
      supabase
        .from("room_bans")
        .select(
          `
          id,
          user_id,
          profiles!room_bans_user_id_fkey (
            id,
            username,
            name,
            avatar_url
          )
        `
        )
        .eq("room_id", roomId)
        .order("created_at", { ascending: false }),
    ])

    if (membersResult.error) {
      console.error("loadManageMembers:", membersResult.error)
      showPopup({ type: "error", message: "Failed to load members" })
      setManageMembers([])
    } else {
      const sorted = [...(membersResult.data ?? [])].sort((a, b) => {
        const aName = String(
          (a as RoomMemberManage).profiles?.username ?? ""
        ).toLowerCase()
        const bName = String(
          (b as RoomMemberManage).profiles?.username ?? ""
        ).toLowerCase()
        return aName.localeCompare(bName)
      })
      setManageMembers(sorted as RoomMemberManage[])
    }

    if (bansResult.error) {
      console.error("loadBannedUsers:", bansResult.error)
      setBannedUsers([])
    } else {
      setBannedUsers((bansResult.data ?? []) as RoomBanManage[])
    }

    setLoadingManageMembers(false)
  }

  async function softRemoveMember(roomId: string, targetUserId: string) {
    return supabase
      .from("room_members")
      .update({ left_at: new Date().toISOString() })
      .eq("room_id", roomId)
      .eq("user_id", targetUserId)
      .is("left_at", null)
  }

  async function handleRemoveMember(targetUserId: string) {
    if (!selectedRoomId || !user?.id) return
    if (targetUserId === user.id) return

    setRemovingMemberId(targetUserId)

    const { error } = await softRemoveMember(selectedRoomId, targetUserId)

    setRemovingMemberId(null)

    if (error) {
      console.error("handleRemoveMember:", error)
      showPopup(persistentError("Remove Failed", "Failed to remove member"))
      return
    }

    showPopup({ type: "success", message: "Member removed" })
    await loadManageMembers(selectedRoomId)
    await loadMemberStats(selectedRoomId)
  }

  async function handleBanMember(targetUserId: string) {
    if (!selectedRoomId || !user?.id) return
    if (targetUserId === user.id) return

    setBanningMemberId(targetUserId)

    const { error: banError } = await supabase.from("room_bans").insert({
      room_id: selectedRoomId,
      user_id: targetUserId,
      banned_by: user.id,
    })

    if (banError && banError.code !== "23505") {
      setBanningMemberId(null)
      console.error("handleBanMember:", banError)
      showPopup(persistentError("Ban Failed", "Failed to ban member"))
      return
    }

    const { error: removeError } = await softRemoveMember(
      selectedRoomId,
      targetUserId
    )

    setBanningMemberId(null)

    if (removeError) {
      console.error("handleBanMember remove:", removeError)
      showPopup({
        type: "warning",
        message: "User banned but failed to remove membership",
      })
    } else {
      showPopup({ type: "success", message: "Member banned" })
    }

    await loadManageMembers(selectedRoomId)
    await loadMemberStats(selectedRoomId)
  }

  async function handleUnbanMember(banId: string) {
    if (!selectedRoomId) return

    setUnbanningBanId(banId)

    const { error } = await supabase
      .from("room_bans")
      .delete()
      .eq("id", banId)
      .eq("room_id", selectedRoomId)

    setUnbanningBanId(null)

    if (error) {
      console.error("handleUnbanMember:", error)
      showPopup({ type: "error", message: "Failed to unban user" })
      return
    }

    showPopup({ type: "success", message: "User unbanned" })
    await loadManageMembers(selectedRoomId)
  }

  async function handleMemberActionConfirm() {
    if (!memberActionConfirm || memberActionBusy) return

    const action = memberActionConfirm

    if (action.kind === "remove") {
      await handleRemoveMember(action.userId)
    } else if (action.kind === "ban") {
      await handleBanMember(action.userId)
    } else {
      await handleUnbanMember(action.banId)
    }

    setMemberActionConfirm(null)
  }

  function memberActionConfirmCopy(confirm: MemberActionConfirm): string {
    if (confirm.kind === "remove") {
      return "Remove this member from the room?"
    }
    if (confirm.kind === "ban") {
      return "Ban this member from the room? They will not be able to rejoin until unbanned."
    }
    return "Allow this user to join the room again?"
  }

  async function loadMemberRooms(userId: string): Promise<Room[]> {
    const { data: memberships, error: memErr } = await supabase
      .from("room_members")
      .select("room_id")
      .eq("user_id", userId)
      .is("left_at", null)

    if (memErr) {
      console.error("room_members fetch:", memErr)
      return []
    }

    const roomIds = [
      ...new Set(
        (memberships ?? []).map((m: { room_id: string }) => m.room_id)
      ),
    ]

    if (roomIds.length === 0) {
      return []
    }

    const { data, error } = await supabase
      .from("rooms")
      .select("id, name, description, slug, image_url, owner_user_id, show_on_profile")
      .in("id", roomIds)
      .order("name", { ascending: true })

    if (error) {
      console.error("rooms fetch:", error)
      return []
    }

    return (data ?? []) as Room[]
  }

  async function joinRoom(roomId: string) {
    if (joiningRoomId) return
    setJoiningRoomId(roomId)

    try {
    const {
      data: { user: authUser },
    } = await supabase.auth.getUser()

    if (!authUser) return

    const { data: existing } = await supabase
      .from("room_members")
      .select("id, left_at")
      .eq("room_id", roomId)
      .eq("user_id", authUser.id)
      .maybeSingle()

    const alreadyActive =
      existing != null && existing.left_at == null

    if (!existing) {
      const { error } = await supabase.from("room_members").insert({
        room_id: roomId,
        user_id: authUser.id,
      })

      if (error && error.code !== "23505") {
        console.error("joinRoom error:", error)
        showPopup({ type: "error", message: "Failed to join room" })
        return
      }
    } else if (!alreadyActive) {
      const { error } = await supabase
        .from("room_members")
        .update({ left_at: null })
        .eq("room_id", roomId)
        .eq("user_id", authUser.id)

      if (error) {
        console.error("joinRoom reactivate:", error)
        showPopup({ type: "error", message: "Failed to join room" })
        return
      }
    }

    const nextRooms = await loadMemberRooms(authUser.id)
    setRooms(nextRooms)
    setInviteTargetRoom(null)
    setSelectedRoomId(roomId)

    if (alreadyActive) {
      showPopup({
        type: "warning",
        message: "You're already in this room",
      })
    } else {
      await createRoomJoinNotification(supabase, roomId)
      notifyGettingStartedChecklistMaybeCompleted()
    }
    } finally {
      setJoiningRoomId(null)
    }
  }

  async function handleLeaveRoom() {
    const {
      data: { user: authUser },
    } = await supabase.auth.getUser()

    if (!authUser || !selectedRoomId) return

    const leftRoomId = selectedRoomId

    const { error } = await supabase
      .from("room_members")
      .update({ left_at: new Date().toISOString() })
      .eq("room_id", leftRoomId)
      .eq("user_id", authUser.id)
      .is("left_at", null)

    if (error) {
      console.error("handleLeaveRoom:", error)
      return
    }

    setRooms((prev) => prev.filter((r) => r.id !== leftRoomId))
    setSelectedRoomId(null)

    const nextRooms = await loadMemberRooms(authUser.id)
    setRooms(nextRooms)

    setActiveMembers((prev) => Math.max(0, prev - 1))
    setLeftMembers((prev) => prev + 1)
    router.push("/trade-rooms")
  }

  async function handleRoomImageUpload(file: File) {
    if (!selectedRoomId) return

    let uploadFile: File = file
    if (file.type?.startsWith("image/")) {
      uploadFile = await compressImage(file)
    }

    const filePath = `room-images/${Date.now()}-${uploadFile.name}`

    const { error: upErr } = await supabase.storage
      .from("avatars")
      .upload(filePath, uploadFile)

    if (upErr) {
      console.error(upErr)
      return
    }

    const { data: urlData } = supabase.storage
      .from("avatars")
      .getPublicUrl(filePath)

    const publicUrl = urlData.publicUrl

    const { error: updErr } = await supabase
      .from("rooms")
      .update({ image_url: publicUrl })
      .eq("id", selectedRoomId)

    if (updErr) {
      console.error(updErr)
      return
    }

    setRoomImage(publicUrl)
    setRooms((prev) =>
      prev.map((r) =>
        r.id === selectedRoomId ? { ...r, image_url: publicUrl } : r
      )
    )
  }

  useEffect(() => {
    const init = async () => {
      const {
        data: { user: authUser },
      } = await supabase.auth.getUser()

      if (!authUser) {
        const returnPath = `/trade-rooms${window.location.search}`
        router.push(`/login?next=${encodeURIComponent(returnPath)}`)
        return
      }
      setUser(authUser)

      const { data: profile } = await supabase
        .from("profiles")
        .select("username")
        .eq("id", authUser.id)
        .maybeSingle()
      if (profile?.username) {
        setUsername(profile.username)
      }

      const nextRooms = await loadMemberRooms(authUser.id)
      setRooms(nextRooms)
      setLoadingRooms(false)

      const rp = searchParams.get("room")
      if (nextRooms.length > 0 && !rp) {
        setSelectedRoomId(nextRooms[0].id)
      }
    }

    void init()
  }, [router, searchParams])

  useEffect(() => {
    if (!roomParam || loadingRooms) return

    const decoded = decodeURIComponent(roomParam.trim())
    const match =
      rooms.find((r) => r.slug === decoded || r.slug === roomParam) ||
      rooms.find((r) => r.id === decoded || r.id === roomParam)

    if (match) {
      setSelectedRoomId(match.id)
      setInviteTargetRoom(null)
      return
    }

    let cancelled = false

    ;(async () => {
      const roomSelect =
        "id, name, description, slug, image_url, owner_user_id, show_on_profile" as const

      const { data: slugRow } = await supabase
        .from("rooms")
        .select(roomSelect)
        .eq("slug", decoded)
        .maybeSingle()

      let row = slugRow

      if (!row && isProfileUuidSegment(decoded)) {
        const { data: idRow } = await supabase
          .from("rooms")
          .select(roomSelect)
          .eq("id", decoded)
          .maybeSingle()
        row = idRow
      }

      if (cancelled) return
      if (!row) {
        setInviteTargetRoom(null)
        return
      }

      setInviteTargetRoom(row as Room)
      setSelectedRoomId(row.id)
    })()

    return () => {
      cancelled = true
    }
  }, [roomParam, rooms, loadingRooms])

  useEffect(() => {
    if (!selectedRoomId || needsJoin) {
      setMessages([])
      setPinnedMessages([])
      setSections([])
      setSelectedSectionId(null)
      setActiveUsers([])
      return
    }

    let cancelled = false

    ;(async () => {
      const { list, activeSectionId } = await loadSections(selectedRoomId)
      if (cancelled) return
      await fetchRoomMessages(selectedRoomId, list, activeSectionId)
    })()

    return () => {
      cancelled = true
    }
  }, [selectedRoomId, needsJoin])

  useEffect(() => {
    if (!selectedRoomId || needsJoin || !user?.id) {
      setActiveUsers([])
      return
    }

    let cancelled = false
    const roomId = selectedRoomId

    const updatePresenceAndCount = async () => {
      if (needsJoinRef.current || !userIdRef.current) return

      const payload = {
        room_id: roomId,
        user_id: userIdRef.current,
        last_seen: new Date().toISOString(),
      }

      console.log("Presence payload:", payload)

      if (!payload.room_id || !payload.user_id) {
        console.warn("Skipping presence update: missing IDs", payload)
        return
      }

      const { error: upsertError } = await supabase
        .from("room_presence")
        .upsert(payload, {
          onConflict: "room_id,user_id",
        })

      if (upsertError) {
        console.error(
          "room_presence upsert FULL:",
          JSON.stringify(upsertError, null, 2)
        )
      }

      const threshold = new Date(Date.now() - 30000).toISOString()
      const { data, error } = await supabase
        .from("room_presence")
        .select(
          `
          user_id,
          profiles (
            id,
            username,
            avatar_url
          )
        `
        )
        .eq("room_id", roomId)
        .gt("last_seen", threshold)

      if (error) {
        console.error("room_presence fetch:", error)
        if (!cancelled) setActiveUsers([])
        return
      }

      const uniqueUsers = Array.from(
        new Map(((data ?? []) as ActivePresence[]).map((u) => [u.user_id, u])).values()
      )
      if (!cancelled) setActiveUsers(uniqueUsers)
    }

    void updatePresenceAndCount()
    const intervalId = window.setInterval(() => {
      void updatePresenceAndCount()
    }, 10000)

    return () => {
      cancelled = true
      window.clearInterval(intervalId)
    }
  }, [selectedRoomId, needsJoin, user?.id])

  useEffect(() => {
    if (!selectedRoomId || needsJoin) return

    const channel = supabase.channel(`room-${selectedRoomId}`)
    channel.on(
      "postgres_changes",
      {
        event: "INSERT",
        schema: "public",
        table: "room_messages",
        filter: `room_id=eq.${selectedRoomId}`,
      },
      async (payload) => {
        const id = (payload.new as { id?: string })?.id
        if (!id) return

        const { data, error } = await supabase
          .from("room_messages")
          .select(
            `
            id,
            room_id,
            user_id,
            seen_by,
            pinned,
            section_id,
            type,
            trade_id,
            content,
            image_url,
            created_at,
            trades (
              id,
              image_url,
              pnl,
              rr
            ),
            profiles (
              username,
              avatar_url
            )
          `
          )
          .eq("id", id)
          .maybeSingle()

        if (error || !data) return

        const row = data as RoomMessage
        const f = sectionFilterRef.current
        if (f.len > 0 && f.id) {
          const sec = sectionsRef.current.find(
            (s: { id: string }) => s.id === f.id
          )
          const nameLower = String(sec?.name ?? "")
            .trim()
            .toLowerCase()
          const generalMerge =
            nameLower === "general" &&
            (row.section_id === f.id || row.section_id == null)
          const strictMatch = nameLower !== "general" && row.section_id === f.id
          if (!generalMerge && !strictMatch) return
        } else if (f.len > 0 && !f.id && row.section_id != null) {
          return
        }

        if (row.pinned === true) {
          void fetchRoomMessages(
            selectedRoomId,
            sectionsRef.current,
            sectionFilterRef.current.id,
            { bypassCache: true }
          )
          return
        }

        setMessages((prev) => {
          if (prev.some((m) => m.id === data.id)) return prev
          return [...prev, row]
        })

        const cacheKey = buildRoomMessagesCacheKey(
          selectedRoomId,
          sectionsRef.current,
          sectionFilterRef.current.id
        )
        setMessagesByRoom((prev) => {
          const entry = prev[cacheKey]
          if (!entry) return prev
          if (entry.main.some((m) => m.id === row.id)) return prev
          return {
            ...prev,
            [cacheKey]: { pinned: entry.pinned, main: [...entry.main, row] },
          }
        })

        const viewerId = userIdRef.current
        if (viewerId && row.user_id !== viewerId) {
          await appendSelfToSeenByForRoomMessage(id, viewerId)
          const next = await fetchUnreadByRoomIds(
            roomIdsForUnreadRef.current,
            viewerId
          )
          setUnreadByRoomId(next)
        }
      }
    )
    channel.subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, [selectedRoomId, needsJoin])

  useEffect(() => {
    if (!selectedRoomId || needsJoin || !user?.id) {
      setTypingUsers([])
      return
    }

    const channel = supabase.channel(`typing-room-${selectedRoomId}`)
    typingChannelRef.current = channel

    channel.on("broadcast", { event: "typing" }, (payload: any) => {
      const typingUser = payload?.payload?.user
      if (!typingUser || typingUser === usernameRef.current) return

      setTypingUsers((prev) => {
        if (prev.includes(typingUser)) return prev
        return [...prev, typingUser]
      })

      window.setTimeout(() => {
        setTypingUsers((prev) => prev.filter((u) => u !== typingUser))
      }, 2000)
    })

    channel.subscribe()

    return () => {
      if (typingChannelRef.current) {
        supabase.removeChannel(typingChannelRef.current)
        typingChannelRef.current = null
      }
      setTypingUsers([])
    }
  }, [selectedRoomId, needsJoin, user?.id])

  // Match Messages (`app/messages/[id]/page.tsx`): scroll only the messages
  // overflow container — never scrollIntoView on inner content, or mobile Safari
  // will scroll the document and hide the Navbar.
  useEffect(() => {
    const el = messagesScrollRef.current
    if (!el) return
    const id = window.setTimeout(() => {
      el.scrollTop = el.scrollHeight
    }, 50)
    return () => window.clearTimeout(id)
  }, [messages])

  const sendTyping = useCallback(() => {
    if (!typingChannelRef.current || !selectedRoomId) return
    void typingChannelRef.current.send({
      type: "broadcast",
      event: "typing",
      payload: { user: username || "User" },
    })
  }, [selectedRoomId, username])

  async function sendMessage() {
    if (sendingMessageRef.current || sendingMessage) return
    if (!user?.id || !selectedRoomId || !canPostInRoom) return
    const content = draft.trim()
    if (!content) return

    sendingMessageRef.current = true
    setSendingMessage(true)

    try {
    const userIsPro = await isUserPro(supabase as any, user.id)
    if (!userIsPro) {
      const limitReached = await reachedMessagesCommentsLimit(
        supabase as any,
        user.id,
        10
      )
      if (limitReached) {
        showPopup(feedbackPresets.messageLimit())
        return
      }
    }

    const { error } = await supabase.from("room_messages").insert({
      room_id: selectedRoomId,
      user_id: user.id,
      content,
      section_id: selectedSectionId,
    })
    if (error) {
      console.error("room_messages insert:", error)
      showPopup({ type: "error", message: handleSupabaseError(error) })
      return
    }

    setDraft("")
    } finally {
      sendingMessageRef.current = false
      setSendingMessage(false)
    }
  }

  async function handleImageUpload(e: ChangeEvent<HTMLInputElement>) {
    if (!user?.id || !selectedRoomId || !canPostInRoom) {
      console.log("[trade-room-image] blocked early", {
        hasUser: Boolean(user?.id),
        selectedRoomId,
        canPostInRoom,
      })
      return
    }
    const file = e.target.files?.[0]
    e.target.value = ""
    if (!file) {
      console.log("[trade-room-image] no file selected")
      return
    }

    console.log("[trade-room-image] image selected", {
      name: file.name,
      type: file.type,
      size: file.size,
      roomId: selectedRoomId,
      sectionId: selectedSectionId,
    })

    const userIsPro = await isUserPro(supabase as any, user.id)
    if (!userIsPro) {
      const limitReached = await reachedMessagesCommentsLimit(
        supabase as any,
        user.id,
        10
      )
      if (limitReached) {
        showPopup(feedbackPresets.messageLimit())
        return
      }
    }

    let uploadFile: File = file
    if (file.type?.startsWith("image/")) {
      uploadFile = await compressImage(file)
    }
    const filePath = `room-images/${Date.now()}-${uploadFile.name}`

    console.log("[trade-room-image] upload started", { filePath, bucket: "screenshots" })

    const { error: uploadError } = await supabase.storage
      .from("screenshots")
      .upload(filePath, uploadFile)

    if (uploadError) {
      console.error("[trade-room-image] upload failed:", uploadError)
      return
    }

    const { data } = supabase.storage.from("screenshots").getPublicUrl(filePath)
    console.log("[trade-room-image] upload completed", { publicUrl: data.publicUrl })

    const insertPayload = {
      room_id: selectedRoomId,
      user_id: user.id,
      type: "image" as const,
      image_url: data.publicUrl,
      section_id: selectedSectionId,
    }
    console.log("[trade-room-image] room message insert payload", insertPayload)

    const { data: insertData, error: insertError } = await supabase
      .from("room_messages")
      .insert(insertPayload)
      .select("id, type, image_url, section_id, room_id, user_id, created_at")
      .maybeSingle()

    console.log("[trade-room-image] room message insert response", {
      insertData,
      insertError,
    })

    if (insertError) {
      console.error("room image message insert:", insertError)
      showPopup({ type: "error", message: handleSupabaseError(insertError) })
    }
  }

  useEffect(() => {
    if (!selectTrade || !user?.id) return

    const loadTrades = async () => {
      const { data, error } = await supabase
        .from("trades")
        .select("id, image_url, pnl, rr, ticker, direction, created_at")
        .eq("user_id", user.id)
        .eq("is_public", true)
        .order("created_at", { ascending: false })
        .limit(30)

      if (error) {
        console.error("trades fetch:", error)
        setUserTrades([])
        return
      }

      setUserTrades(data || [])
    }

    void loadTrades()
  }, [selectTrade, user?.id])

  async function sendTradeMessage(trade: any) {
    if (!user?.id || !selectedRoomId || !canPostInRoom) return

    const userIsPro = await isUserPro(supabase as any, user.id)
    if (!userIsPro) {
      const limitReached = await reachedMessagesCommentsLimit(
        supabase as any,
        user.id,
        10
      )
      if (limitReached) {
        showPopup(feedbackPresets.messageLimit())
        return
      }
    }

    const { error } = await supabase.from("room_messages").insert({
      room_id: selectedRoomId,
      user_id: user.id,
      type: "trade",
      trade_id: trade.id,
      content: "Shared a trade",
      section_id: selectedSectionId,
    })

    if (error) {
      console.error("room trade message insert:", error)
      showPopup({ type: "error", message: handleSupabaseError(error) })
      return
    }

    setSelectTrade(false)
  }

  return (
    <>
      <Navbar />
      <FeedbackModal {...feedbackModalProps} />
      <div className="flex h-[calc(100dvh-4rem)] min-h-0 flex-col overflow-hidden bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 py-2 text-white">
        <div className="mx-auto flex h-full min-h-0 w-full max-w-6xl flex-col overflow-visible rounded-2xl border border-white/10 bg-black/25 md:flex-row md:overflow-hidden">
          <aside className="shrink-0 border-b border-white/10 bg-[#0b1220]/80 md:w-72 md:border-b-0 md:border-r">
            <div className="border-b border-white/10 px-4 py-3">
              <h1 className="hidden text-lg font-semibold md:block">Trade Rooms</h1>
              <button
                type="button"
                className="flex w-full min-h-[48px] items-center justify-between gap-3 rounded-lg border border-white/10 bg-[#0f172a]/60 px-3 py-2.5 text-left transition hover:bg-white/5 md:hidden"
                onClick={() => setMobileRoomsOpen((o) => !o)}
                aria-expanded={mobileRoomsOpen}
                aria-controls="trade-rooms-list"
              >
                <div className="min-w-0 flex-1">
                  <p className="text-[11px] font-medium uppercase tracking-wide text-gray-400">
                    Trade Rooms
                  </p>
                  <p className="truncate text-sm font-semibold text-white">
                    {selectedRoom?.name || "Select room"}
                  </p>
                </div>
                <svg
                  className={`h-5 w-5 shrink-0 text-gray-300 transition-transform duration-200 ${
                    mobileRoomsOpen ? "rotate-180" : ""
                  }`}
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  aria-hidden
                >
                  <path d="M6 9l6 6 6-6" />
                </svg>
              </button>
            </div>
            <div
              id="trade-rooms-list"
              className={`grid overflow-hidden transition-[grid-template-rows] duration-200 ease-out ${
                mobileRoomsOpen ? "grid-rows-[1fr]" : "grid-rows-[0fr]"
              } md:grid-rows-[1fr]`}
            >
              <div className="min-h-0 overflow-hidden">
                <div className="max-h-[min(50svh,280px)] overflow-y-auto p-2 md:max-h-none">
                  {loadingRooms ? (
                    <div className="space-y-1 px-1">
                      {Array.from({ length: 5 }).map((_, i) => (
                        <div key={i} className="flex items-center gap-3 rounded-lg px-3 py-2">
                          <div className="h-8 w-8 shrink-0 animate-pulse rounded-full bg-white/10" />
                          <div className="h-4 flex-1 max-w-[140px] animate-pulse rounded bg-white/10" />
                        </div>
                      ))}
                    </div>
                  ) : rooms.length === 0 ? (
                    <p className="px-2 py-3 text-sm text-gray-400">No rooms found.</p>
                  ) : (
                    sortedSidebarRooms.map((room) => {
                      const selected = room.id === selectedRoomId
                      const isOwnRoom =
                        user?.id != null && room.owner_user_id === user.id
                      const itemClass =
                        `mb-1 flex min-h-[44px] w-full items-center gap-3 rounded-lg px-3 py-2 text-left text-sm transition ` +
                        (isOwnRoom
                          ? selected
                            ? `border border-blue-400/40 bg-blue-500/25 font-semibold text-blue-100`
                            : `border border-blue-400/30 bg-blue-500/10 font-semibold text-blue-300 hover:bg-blue-500/15`
                          : selected
                            ? `bg-blue-500/25 text-blue-100`
                            : `text-gray-200 hover:bg-white/10`)
                      const sidebarAvatarSrc =
                        [room.image_url, room.avatar_url]
                          .map((v) =>
                            v != null && String(v).trim() !== ""
                              ? String(v).trim()
                              : ""
                          )
                          .find(Boolean) || "/default-avatar.png"
                      return (
                        <button
                          key={room.id}
                          type="button"
                          onClick={() => {
                            setSelectedRoomId(room.id)
                            setMobileRoomsOpen(false)
                          }}
                          className={itemClass}
                        >
                          <img
                            src={sidebarAvatarSrc}
                            alt="room avatar"
                            loading="lazy"
                            decoding="async"
                            className="h-8 w-8 shrink-0 rounded-full object-cover"
                            onError={(e) => {
                              e.currentTarget.src = "/default-avatar.png"
                            }}
                          />
                          <div className="flex min-w-0 flex-1 items-center">
                            <span className="min-w-0 flex-1 truncate">
                              {room.name || "Room"}
                            </span>
                            {unreadByRoomId[room.id] ? (
                              <span
                                className="ml-2 h-2 w-2 shrink-0 rounded-full bg-blue-400"
                                aria-label="Unread messages"
                              />
                            ) : null}
                          </div>
                        </button>
                      )
                    })
                  )}
                </div>
              </div>
            </div>
          </aside>

          <section className="flex min-h-0 w-full min-w-0 flex-1 flex-col">
            <div className="border-b border-white/10 px-4 py-3">
              <div className="flex items-center gap-3">
                <img
                  src={
                    (roomImage ??
                      selectedRoom?.image_url ??
                      inviteTargetRoom?.image_url) ||
                    "/default-avatar.png"
                  }
                  alt="Room Avatar"
                  loading="lazy"
                  decoding="async"
                  className="h-12 w-12 shrink-0 rounded-full object-cover"
                />

                <div className="flex min-w-0 flex-1 flex-col justify-center">
                  <div className="flex flex-wrap items-center gap-2">
                    <h2 className="truncate text-lg font-semibold text-white">
                      {selectedRoom?.name ??
                        inviteTargetRoom?.name ??
                        "Select a room"}
                    </h2>

                    {!isOwner && selectedRoomId && !needsJoin ? (
                      <button
                        type="button"
                        onClick={() => void handleLeaveRoom()}
                        className="rounded-md bg-red-500/10 px-3 py-1 text-xs text-red-400 hover:bg-red-500/20"
                      >
                        Leave Room
                      </button>
                    ) : null}

                    {isOwner && selectedRoomId && !needsJoin ? (
                      <div className="flex shrink-0 items-center gap-2">
                        <button
                          type="button"
                          aria-label="Room settings"
                          onClick={() => setShowRoomSettings(true)}
                          className="flex items-center justify-center rounded-md bg-white/10 p-2 hover:bg-white/20"
                        >
                          ⚙️
                        </button>
                        <button
                          type="button"
                          aria-label="Share invite"
                          onClick={() => setShowInviteModal(true)}
                          className="flex items-center justify-center rounded-md bg-white/10 p-2 hover:bg-white/20"
                        >
                          <svg
                            xmlns="http://www.w3.org/2000/svg"
                            className="h-5 w-5 text-blue-300"
                            fill="none"
                            viewBox="0 0 24 24"
                            stroke="currentColor"
                          >
                            <path
                              strokeLinecap="round"
                              strokeLinejoin="round"
                              strokeWidth={2}
                              d="M12 16V4m0 0l-4 4m4-4l4 4M4 20h16"
                            />
                          </svg>
                        </button>
                      </div>
                    ) : null}
                  </div>

                  {isOwner && selectedRoomId && !needsJoin ? (
                    <p className="text-sm text-gray-400">
                      {activeMembers} members • {leftMembers} left
                    </p>
                  ) : null}
                </div>
              </div>

              {selectedRoomId && !needsJoin ? (
                <div className="mt-2 flex items-center">
                  <div className="flex items-center space-x-[-8px]">
                    {activeUsers.slice(0, 3).map((u) => (
                      <ProfileAvatarLink
                        key={u.user_id}
                        userId={u.user_id}
                        username={u.profiles?.username}
                        src={u.profiles?.avatar_url}
                        imgClassName="h-8 w-8 rounded-full border-2 border-[#0B1120] object-cover"
                      />
                    ))}
                  </div>
                  {activeUsers.length > 3 ? (
                    <div className="ml-1 text-xs text-gray-400">
                      +{activeUsers.length - 3}
                    </div>
                  ) : null}
                  <span className="ml-2 text-sm text-gray-400">
                    {activeUsers.length} active traders
                  </span>
                </div>
              ) : null}
            </div>

            {setupMode && isOwner && selectedRoomId ? (
              <div className="border-b border-green-500/15 px-4 pb-4">
                <div className="rounded-lg border border-green-500/20 bg-green-500/10 p-4">
                  <h2 className="mb-2 text-lg font-semibold text-green-300">
                    Set up your Trade Room
                  </h2>

                  <p className="mb-3 text-sm text-gray-400">
                    Customize your room, create channels, and share your invite
                    link.
                  </p>

                  <div className="mb-3">
                    <p className="mb-1 text-sm font-medium text-gray-300">
                      Trade Room Picture
                    </p>
                    <label className="inline-flex cursor-pointer items-center rounded-md border border-white/10 bg-white/10 px-3 py-2 text-sm font-medium text-gray-200 transition hover:bg-white/15">
                      Choose Trade Room Picture
                      <input
                        type="file"
                        accept="image/*"
                        className="sr-only"
                        onChange={(e) => {
                          const file = e.target.files?.[0]
                          e.target.value = ""
                          if (file) void handleRoomImageUpload(file)
                        }}
                      />
                    </label>
                  </div>

                  <input
                    type="text"
                    value={roomName}
                    onChange={(e) => setRoomName(e.target.value)}
                    className="mb-2 w-full rounded-md border border-white/10 bg-black/30 px-3 py-2 text-sm text-white placeholder:text-gray-500"
                    placeholder="Room name"
                  />

                  <button
                    type="button"
                    onClick={() => void handleRenameRoom()}
                    className="rounded-md bg-green-500/20 px-3 py-1 text-sm text-green-200 hover:bg-green-500/30"
                  >
                    Save Name
                  </button>

                  <label className="mt-3 flex items-center gap-2 text-sm text-gray-300">
                    <input
                      type="checkbox"
                      checked={showOnProfile}
                      onChange={(e) => setShowOnProfile(e.target.checked)}
                    />
                    Show on my profile
                  </label>

                  <p className="mt-1 text-xs text-gray-500">
                    If off, users can only join via invite link.
                  </p>

                  <div className="mt-3">
                    <p className="mb-1 text-xs text-gray-400">Invite link</p>

                    <div className="flex gap-2">
                      <input
                        readOnly
                        value={inviteLinkDisplay}
                        className="flex-1 rounded border border-white/10 bg-black/30 px-2 py-1 text-xs text-gray-200"
                      />

                      <button
                        type="button"
                        onClick={() => {
                          if (!inviteLinkDisplay) return
                          void navigator.clipboard.writeText(inviteLinkDisplay)
                        }}
                        className="rounded bg-white/10 px-2 py-1 text-xs text-gray-200 hover:bg-white/15"
                      >
                        Copy
                      </button>
                    </div>
                  </div>

                  <button
                    type="button"
                    onClick={() => {
                      if (!inviteRoomKey) return
                      router.push(
                        `/trade-rooms?room=${encodeURIComponent(inviteRoomKey)}`
                      )
                    }}
                    className="mt-3 rounded-md bg-green-500/20 px-3 py-1 text-sm text-green-200 hover:bg-green-500/30"
                  >
                    Finish Setting Up
                  </button>
                </div>
              </div>
            ) : null}

            {needsJoin && inviteTargetRoom ? (
              <div className="flex flex-1 flex-col items-center justify-center px-6 py-16 text-center">
                <p className="mb-6 max-w-md text-gray-300">
                  Join{" "}
                  <span className="font-semibold text-white">
                    {inviteTargetRoom.name || "this room"}
                  </span>{" "}
                  to view channels and messages.
                </p>
                <button
                  type="button"
                  onClick={() => void joinRoom(inviteTargetRoom.id)}
                  disabled={joiningRoomId === inviteTargetRoom.id}
                  className="rounded-lg bg-green-500/30 px-6 py-3 text-sm font-medium text-green-100 hover:bg-green-500/40 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  {joiningRoomId === inviteTargetRoom.id
                    ? "Joining…"
                    : "Join This Trade Room"}
                </button>
              </div>
            ) : (
              <>
                <div className="flex min-h-0 min-w-0 flex-1 flex-col md:flex-row">
              {sections.length > 0 ? (
                <div className="flex max-h-[min(40svh,220px)] shrink-0 flex-col border-b border-white/10 p-2 md:max-h-none md:w-48 md:border-b-0 md:border-r md:border-white/10 md:p-2">
                  <div className="flex max-h-[min(36svh,180px)] flex-row gap-1 overflow-x-auto md:max-h-none md:flex-col md:gap-0 md:overflow-y-auto">
                    {sections.map((section) => (
                      <div
                        key={section.id}
                        className={`flex min-w-[8rem] items-stretch rounded-md md:min-w-0 ${
                          selectedSectionId === section.id
                            ? "bg-green-500/20 text-green-300"
                            : "text-gray-400"
                        }`}
                      >
                        <button
                          type="button"
                          onClick={() => {
                            setSelectedSectionId(section.id)
                            if (selectedRoomId) {
                              void fetchRoomMessages(
                                selectedRoomId,
                                sections,
                                section.id
                              )
                            }
                          }}
                          className="min-w-0 flex-1 px-3 py-2 text-left hover:bg-white/5"
                        >
                          <span className="block truncate font-medium text-sm">
                            {section.name}
                          </span>
                        </button>
                        {isOwner ? (
                          <button
                            type="button"
                            aria-label="Channel settings"
                            onClick={(e) => {
                              e.stopPropagation()
                              openChannelSettings(section)
                            }}
                            className="shrink-0 px-2 py-2 text-xs text-gray-500 hover:text-white"
                          >
                            ✏️
                          </button>
                        ) : null}
                      </div>
                    ))}
                  </div>
                  {isOwner && sections.length < 5 ? (
                    <button
                      type="button"
                      onClick={() => setShowCreateSectionModal(true)}
                      className="mt-2 w-full rounded-md px-3 py-2 text-left text-sm text-green-400 hover:bg-white/5"
                    >
                      + Add Channel
                    </button>
                  ) : null}
                </div>
              ) : null}

              <div
                ref={messagesScrollRef}
                className="min-h-0 min-w-0 max-h-[min(65svh,525px)] flex-1 overflow-y-auto px-4 py-3 md:max-h-none"
              >
              {!selectedRoomId ? (
                <p className="text-sm text-gray-400">Pick a room to start chatting.</p>
              ) : loadingMessages ? (
                <div className="space-y-3">
                  {Array.from({ length: 6 }).map((_, i) => (
                    <SkeletonMessage key={i} />
                  ))}
                </div>
              ) : (
                <>
                  {messages.length === 0 && pinnedMessages.length === 0 ? (
                    <p className="text-sm text-gray-400">No messages yet.</p>
                  ) : null}
                  {messages.length > 0 ? (
                <div className="space-y-3">
                  {messages.map((msg) => (
                    <div key={msg.id} className="group relative rounded-xl bg-white/5 p-3">
                      <div className="mb-1 flex flex-wrap items-center gap-2">
                        <ProfileAvatarLink
                          userId={msg.user_id}
                          username={msg.profiles?.username}
                          src={msg.profiles?.avatar_url}
                          imgClassName="h-6 w-6 shrink-0 rounded-full"
                        />
                        <ProfileUsernameLink
                          userId={msg.user_id}
                          username={msg.profiles?.username}
                          className="text-sm font-semibold"
                        />
                        <span className="text-xs text-gray-400">
                          {formatEST(String(msg.created_at ?? ""))}
                        </span>
                        {isOwner ? (
                          <button
                            type="button"
                            onClick={() =>
                              void handleTogglePin(msg.id, msg.pinned)
                            }
                            className={`text-xs ml-2 ${
                              msg.pinned ? "text-yellow-400" : "text-gray-400"
                            }`}
                          >
                            📌
                          </button>
                        ) : null}
                        <RoomMessageActionsMenu
                          message={msg}
                          viewerUserId={user?.id}
                          isRoomOwner={isOwner}
                          activeMenuId={activeMessageMenuId}
                          setActiveMenuId={setActiveMessageMenuId}
                          onEdit={() => startEditMessage(msg)}
                          onDelete={() => void handleDeleteMessage(msg.id)}
                          deleting={deletingMessageId === msg.id}
                        />
                      </div>

                      <div className="text-sm">
                        {msg.type === "image" ? (
                          <img
                            src={msg.image_url || ""}
                            className="mt-1 max-w-xs rounded"
                            alt=""
                            loading="lazy"
                            decoding="async"
                          />
                        ) : msg.type === "trade" ? (
                          msg.trades ? (
                          <div className="mt-1 rounded bg-white/5 p-2 max-w-xs">
                            {tradeImageSrc(msg.trades.image_url) ? (
                              <img
                                src={tradeImageSrc(msg.trades.image_url) || ""}
                                className="rounded"
                                alt=""
                                loading="lazy"
                                decoding="async"
                              />
                            ) : null}
                            <p className="mt-1 text-xs">
                              PnL: {formatMoneyUnknown(msg.trades.pnl, { empty: "—" })} | RR:{" "}
                              {formatRR(msg.trades.rr)}
                            </p>
                          </div>
                          ) : (
                            <p className="mt-1 text-xs italic text-gray-400">
                              Trade unavailable or private.
                            </p>
                          )
                        ) : editingMessageId === msg.id &&
                          canEditRoomMessage(user?.id, msg) ? (
                          <div className="space-y-2">
                            <textarea
                              value={editingMessageContent}
                              onChange={(e) =>
                                setEditingMessageContent(e.target.value)
                              }
                              rows={3}
                              className="w-full rounded-lg border border-white/10 bg-black/20 px-3 py-2 text-sm text-white"
                            />
                            <div className="flex gap-2">
                              <button
                                type="button"
                                onClick={() =>
                                  void handleSaveEditMessage(msg.id)
                                }
                                disabled={!editingMessageContent.trim()}
                                className="rounded-md bg-green-600 px-3 py-1 text-xs text-white hover:bg-green-500 disabled:opacity-50"
                              >
                                Save
                              </button>
                              <button
                                type="button"
                                onClick={cancelEditMessage}
                                className="rounded-md px-3 py-1 text-xs text-gray-400 hover:text-white"
                              >
                                Cancel
                              </button>
                            </div>
                          </div>
                        ) : (
                          <p className="break-words text-sm text-white">{msg.content}</p>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
                  ) : null}
                  {pinnedMessages.length > 0 ? (
                    <div className="mt-3 rounded-lg border border-yellow-500/20 bg-yellow-500/10 p-3">
                      <p className="mb-2 text-xs text-yellow-400">Pinned</p>

                      <div className="space-y-2">
                        {pinnedMessages.map((msg) => (
                          <div key={msg.id} className="group relative rounded-lg bg-black/20 p-2">
                            <div className="mb-1 flex items-center justify-between gap-2">
                              <ProfileUsernameLink
                                userId={msg.user_id}
                                username={msg.profiles?.username}
                                className="text-xs text-gray-400"
                              />
                              <div className="flex shrink-0 items-center gap-1">
                                {isOwner ? (
                                  <button
                                    type="button"
                                    onClick={() =>
                                      void handleTogglePin(msg.id, msg.pinned)
                                    }
                                    className={`text-xs ${
                                      msg.pinned ? "text-yellow-400" : "text-gray-400"
                                    }`}
                                  >
                                    📌
                                  </button>
                                ) : null}
                                <RoomMessageActionsMenu
                                  message={msg}
                                  viewerUserId={user?.id}
                                  isRoomOwner={isOwner}
                                  activeMenuId={activeMessageMenuId}
                                  setActiveMenuId={setActiveMessageMenuId}
                                  onEdit={() => startEditMessage(msg)}
                                  onDelete={() => void handleDeleteMessage(msg.id)}
                                  deleting={deletingMessageId === msg.id}
                                />
                              </div>
                            </div>
                            <div className="text-sm text-white">
                              {msg.type === "image" ? (
                                <img
                                  src={msg.image_url || ""}
                                  className="mt-1 max-h-24 rounded"
                                  alt=""
                                  loading="lazy"
                                  decoding="async"
                                />
                              ) : msg.type === "trade" && msg.trades ? (
                                <span>
                                  Trade · {msg.trades.ticker ?? "—"} · PnL{" "}
                                  {msg.trades.pnl ?? "—"}
                                </span>
                              ) : editingMessageId === msg.id &&
                                canEditRoomMessage(user?.id, msg) ? (
                                <div className="space-y-2">
                                  <textarea
                                    value={editingMessageContent}
                                    onChange={(e) =>
                                      setEditingMessageContent(e.target.value)
                                    }
                                    rows={3}
                                    className="w-full rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white"
                                  />
                                  <div className="flex gap-2">
                                    <button
                                      type="button"
                                      onClick={() =>
                                        void handleSaveEditMessage(msg.id)
                                      }
                                      disabled={!editingMessageContent.trim()}
                                      className="rounded-md bg-green-600 px-3 py-1 text-xs text-white hover:bg-green-500 disabled:opacity-50"
                                    >
                                      Save
                                    </button>
                                    <button
                                      type="button"
                                      onClick={cancelEditMessage}
                                      className="rounded-md px-3 py-1 text-xs text-gray-400 hover:text-white"
                                    >
                                      Cancel
                                    </button>
                                  </div>
                                </div>
                              ) : (
                                <span className="break-words">{msg.content}</span>
                              )}
                            </div>
                          </div>
                        ))}
                      </div>
                    </div>
                  ) : null}
                </>
              )}
              </div>
                </div>

                {selectedRoomId &&
                !needsJoin &&
                !canPostInRoom &&
                !isOwner ? (
                  <div className="p-3 text-sm text-gray-400">
                    {isBetaAnnouncementsLocked
                      ? "Only admins can post in this section."
                      : "Only the room owner can post in this section."}
                  </div>
                ) : (
                  <DmStyleComposer
                    value={draft}
                    onChange={(v) => {
                      setDraft(v)
                      sendTyping()
                    }}
                    onSend={() => void sendMessage()}
                    placeholder={
                      !selectedRoomId
                        ? "Select a room first"
                        : needsJoin
                          ? "Join this room to chat"
                          : "Message room..."
                    }
                    textDisabled={!canPostInRoom}
                    sendDisabled={
                      !canPostInRoom || !draft.trim() || sendingMessage
                    }
                    onImageChange={(e) => void handleImageUpload(e)}
                    imageDisabled={!canPostInRoom}
                    onTradeClick={() => setSelectTrade(true)}
                    tradeDisabled={!canPostInRoom}
                    beforeRow={
                      typingUsers.length > 0 ? (
                        <p className="text-xs text-gray-400">
                          {typingUsers.join(", ")} typing...
                        </p>
                      ) : null
                    }
                  />
                )}
              </>
            )}
          </section>
        </div>
      </div>

      {showCreateSectionModal ? (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
          onClick={() => setShowCreateSectionModal(false)}
          role="presentation"
        >
          <div
            className="w-[350px] rounded-lg bg-[#0b1f3a] p-6 text-white shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="mb-3 text-lg font-semibold">Create Channel</h2>

            <input
              type="text"
              value={newSectionName}
              onChange={(e) => setNewSectionName(e.target.value)}
              className="mb-3 w-full rounded border border-white/10 bg-black/30 px-3 py-2 text-sm text-white placeholder:text-gray-500"
              placeholder="Channel name"
            />

            <label className="mb-4 flex cursor-pointer items-center gap-2 text-sm text-gray-300">
              <input
                type="checkbox"
                className="rounded border-white/20 bg-black/30"
                checked={newSectionAllowChat}
                onChange={(e) => setNewSectionAllowChat(e.target.checked)}
              />
              Open discussion
            </label>

            <div className="flex justify-end gap-3">
              <button
                type="button"
                onClick={() => setShowCreateSectionModal(false)}
                className="text-sm text-gray-400 hover:text-white"
              >
                Cancel
              </button>

              <button
                type="button"
                onClick={() => void handleCreateSection()}
                className="rounded bg-green-500/20 px-4 py-2 text-sm text-white hover:bg-green-500/30"
              >
                Create
              </button>
            </div>
          </div>
        </div>
      ) : null}

      {editingSection ? (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
          onClick={() => {
            if (deletingSectionId) return
            setEditingSection(null)
          }}
          role="presentation"
        >
          <div
            className="w-full max-w-[400px] rounded-lg bg-[#0b1f3a] p-6 text-white shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="mb-3 text-lg font-semibold">Channel Settings</h2>

            <div className="border-t border-white/10 pt-4">
              <p className="mb-1 text-sm font-medium text-gray-300">
                Channel Name
              </p>
              <input
                type="text"
                value={editSectionName}
                onChange={(e) => setEditSectionName(e.target.value)}
                className="mb-3 w-full rounded border border-white/10 bg-black/30 px-3 py-2 text-sm text-white placeholder:text-gray-500"
                placeholder="Channel name"
              />

              <label className="flex cursor-pointer items-center gap-2 text-sm text-gray-300">
                <input
                  type="checkbox"
                  className="rounded border-white/20 bg-black/30"
                  checked={editAllowChat}
                  onChange={(e) => setEditAllowChat(e.target.checked)}
                />
                Members can chat
              </label>
            </div>

            <div className="mt-4 space-y-2 border-t border-white/10 pt-4">
              <button
                type="button"
                onClick={() => void handleSaveSectionEdit()}
                className="w-full rounded bg-green-500/20 px-4 py-2 text-sm text-green-100 hover:bg-green-500/30"
              >
                Save Changes
              </button>

              {sections.length > 1 ? (
                <button
                  type="button"
                  disabled={deletingSectionId != null}
                  onClick={() => requestDeleteFromChannelSettings()}
                  className="w-full rounded bg-red-500/10 px-4 py-2 text-sm text-red-400 hover:bg-red-500/20 disabled:opacity-50"
                >
                  Delete Channel
                </button>
              ) : null}
            </div>
          </div>
        </div>
      ) : null}

      {showInviteModal ? (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
          onClick={() => setShowInviteModal(false)}
          role="presentation"
        >
          <div
            className="w-[320px] rounded-lg bg-[#0b1f3a] p-5"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="mb-3 text-lg text-white">Invite Link</h2>

            <input
              readOnly
              value={inviteLink}
              className="mb-3 w-full rounded border border-white/10 bg-black/30 px-2 py-1 text-xs text-gray-200"
            />

            <div className="flex items-center justify-between">
              <button
                type="button"
                onClick={() => {
                  if (!inviteLink) return
                  void navigator.clipboard.writeText(inviteLink)
                }}
                className="rounded bg-green-500/20 px-3 py-1 text-xs text-green-400 hover:bg-green-500/30"
              >
                Copy
              </button>

              <button
                type="button"
                onClick={() => setShowInviteModal(false)}
                className="text-xs text-gray-400"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      ) : null}

      {showManageMembers && isOwner && selectedRoomId ? (
        <div
          className="fixed inset-0 z-[60] flex items-center justify-center bg-black/50 p-4"
          onClick={() => {
            if (memberActionBusy || memberActionConfirm) return
            setShowManageMembers(false)
          }}
          role="presentation"
        >
          <div
            className="relative flex w-full max-w-[400px] max-h-[min(85svh,560px)] flex-col rounded-lg bg-[#0b1f3a] p-6 text-white shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="mb-3 shrink-0 text-lg font-semibold">Manage Members</h2>

            <input
              type="text"
              value={memberSearchQuery}
              onChange={(e) => setMemberSearchQuery(e.target.value)}
              className="mb-3 w-full shrink-0 rounded border border-white/10 bg-black/30 px-3 py-2 text-sm text-white placeholder:text-gray-500"
              placeholder="Search members"
            />

            <div className="min-h-0 flex-1 overflow-y-auto">
              {loadingManageMembers ? (
                <div className="space-y-2">
                  {Array.from({ length: 5 }).map((_, i) => (
                    <SkeletonLeaderboardRow key={i} className="rounded-lg bg-white/5 px-2" />
                  ))}
                </div>
              ) : (
                <>
                  {filteredManageMembers.length === 0 ? (
                    manageMembers.length === 0 ? (
                      <EmptyState
                        title="No Members Yet"
                        className="py-6"
                      />
                    ) : (
                      <EmptyState
                        title="No Members Found"
                        description="Try adjusting your search."
                        className="py-6"
                      />
                    )
                  ) : (
                    <div className="space-y-2">
                      {filteredManageMembers.map((member) => {
                        const isSelf = member.user_id === user?.id
                        const displayName = member.profiles?.name?.trim()
                        const username = member.profiles?.username?.trim()
                        const avatarSrc =
                          member.profiles?.avatar_url?.trim() ||
                          "/default-avatar.png"
                        const isRemoving = removingMemberId === member.user_id
                        const isBanning = banningMemberId === member.user_id

                        return (
                          <div
                            key={member.user_id}
                            className="flex items-center gap-3 rounded-lg bg-white/5 p-2"
                          >
                            <ProfileAvatarLink
                              userId={member.user_id}
                              username={username}
                              src={avatarSrc}
                              imgClassName="h-9 w-9 shrink-0 rounded-full object-cover"
                            />
                            <div className="min-w-0 flex-1">
                              <ProfileUsernameLink
                                userId={member.user_id}
                                username={username}
                                className="block truncate text-sm font-medium text-white"
                              />
                              {displayName ? (
                                <p className="truncate text-xs text-gray-400">
                                  {displayName}
                                </p>
                              ) : null}
                            </div>
                            {isSelf ? (
                              <span className="shrink-0 text-xs text-gray-500">
                                Owner
                              </span>
                            ) : (
                              <div className="flex shrink-0 items-center gap-1">
                                <button
                                  type="button"
                                  disabled={memberActionBusy}
                                  onClick={() =>
                                    setMemberActionConfirm({
                                      kind: "ban",
                                      userId: member.user_id,
                                    })
                                  }
                                  className="inline-flex items-center gap-1 rounded bg-orange-500/10 px-2 py-1 text-xs text-orange-400 hover:bg-orange-500/20 disabled:opacity-50"
                                >
                                  {isBanning ? (
                                    <>
                                      <ActionSpinner className="border-orange-400" />
                                      Banning...
                                    </>
                                  ) : (
                                    "Ban"
                                  )}
                                </button>
                                <button
                                  type="button"
                                  disabled={memberActionBusy}
                                  onClick={() =>
                                    setMemberActionConfirm({
                                      kind: "remove",
                                      userId: member.user_id,
                                    })
                                  }
                                  className="inline-flex items-center gap-1 rounded bg-red-500/10 px-2 py-1 text-xs text-red-400 hover:bg-red-500/20 disabled:opacity-50"
                                >
                                  {isRemoving ? (
                                    <>
                                      <ActionSpinner className="border-red-400" />
                                      Removing...
                                    </>
                                  ) : (
                                    "Remove"
                                  )}
                                </button>
                              </div>
                            )}
                          </div>
                        )
                      })}
                    </div>
                  )}

                  <div className="mt-4 border-t border-white/10 pt-4">
                    <p className="mb-2 text-sm font-medium text-gray-300">
                      Banned Users
                    </p>
                    {filteredBannedUsers.length === 0 ? (
                      <p className="py-2 text-sm text-gray-400">
                        {bannedUsers.length === 0
                          ? "No banned users."
                          : "No banned users match your search."}
                      </p>
                    ) : (
                      <div className="space-y-2">
                        {filteredBannedUsers.map((ban) => {
                          const displayName = ban.profiles?.name?.trim()
                          const username = ban.profiles?.username?.trim()
                          const avatarSrc =
                            ban.profiles?.avatar_url?.trim() ||
                            "/default-avatar.png"
                          const isUnbanning = unbanningBanId === ban.id

                          return (
                            <div
                              key={ban.id}
                              className="flex items-center gap-3 rounded-lg bg-white/5 p-2"
                            >
                              <ProfileAvatarLink
                                userId={ban.user_id}
                                username={username}
                                src={avatarSrc}
                                imgClassName="h-9 w-9 shrink-0 rounded-full object-cover"
                              />
                              <div className="min-w-0 flex-1">
                                <ProfileUsernameLink
                                  userId={ban.user_id}
                                  username={username}
                                  className="block truncate text-sm font-medium text-white"
                                />
                                {displayName ? (
                                  <p className="truncate text-xs text-gray-400">
                                    {displayName}
                                  </p>
                                ) : null}
                              </div>
                              <button
                                type="button"
                                disabled={memberActionBusy}
                                onClick={() =>
                                  setMemberActionConfirm({
                                    kind: "unban",
                                    banId: ban.id,
                                  })
                                }
                                className="inline-flex shrink-0 items-center gap-1 rounded bg-green-500/10 px-2 py-1 text-xs text-green-400 hover:bg-green-500/20 disabled:opacity-50"
                              >
                                {isUnbanning ? (
                                  <>
                                    <ActionSpinner className="border-green-400" />
                                    Unbanning...
                                  </>
                                ) : (
                                  "Unban"
                                )}
                              </button>
                            </div>
                          )
                        })}
                      </div>
                    )}
                  </div>
                </>
              )}
            </div>

            <div className="mt-4 flex shrink-0 justify-end">
              <button
                type="button"
                disabled={memberActionBusy || memberActionConfirm != null}
                onClick={() => setShowManageMembers(false)}
                className="text-sm text-gray-400 hover:text-white disabled:opacity-50"
              >
                Close
              </button>
            </div>

            {memberActionConfirm ? (
              <div
                className="absolute inset-0 z-10 flex items-center justify-center rounded-lg bg-black/60 p-4"
                onClick={(e) => e.stopPropagation()}
              >
                <div className="w-full max-w-[320px] rounded-lg border border-white/10 bg-[#0b1f3a] p-5 shadow-xl">
                  <p className="mb-4 text-sm text-gray-200">
                    {memberActionConfirmCopy(memberActionConfirm)}
                  </p>
                  <div className="flex justify-end gap-3">
                    <button
                      type="button"
                      disabled={memberActionBusy}
                      onClick={() => setMemberActionConfirm(null)}
                      className="text-sm text-gray-400 hover:text-white disabled:opacity-50"
                    >
                      Cancel
                    </button>
                    <button
                      type="button"
                      disabled={memberActionBusy}
                      onClick={() => void handleMemberActionConfirm()}
                      className={
                        memberActionConfirm.kind === "unban"
                          ? "inline-flex items-center gap-1.5 rounded bg-green-500/20 px-3 py-1.5 text-sm text-green-100 hover:bg-green-500/30 disabled:opacity-50"
                          : memberActionConfirm.kind === "ban"
                            ? "inline-flex items-center gap-1.5 rounded bg-orange-500/20 px-3 py-1.5 text-sm text-orange-100 hover:bg-orange-500/30 disabled:opacity-50"
                            : "inline-flex items-center gap-1.5 rounded bg-red-500/20 px-3 py-1.5 text-sm text-red-100 hover:bg-red-500/30 disabled:opacity-50"
                      }
                    >
                      {memberActionBusy ? (
                        <>
                          <ActionSpinner />
                          Confirming...
                        </>
                      ) : memberActionConfirm.kind === "unban" ? (
                        "Unban"
                      ) : memberActionConfirm.kind === "ban" ? (
                        "Ban"
                      ) : (
                        "Remove"
                      )}
                    </button>
                  </div>
                </div>
              </div>
            ) : null}
          </div>
        </div>
      ) : null}

      {showRoomSettings && isOwner && selectedRoomId ? (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
          onClick={() => {
            if (deletingSectionId || deleteSectionConfirm) return
            setShowRoomSettings(false)
          }}
          role="presentation"
        >
          <div
            className="relative w-full max-w-[400px] rounded-lg bg-[#0b1f3a] p-6 text-white shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="mb-3 text-lg font-semibold">Room Settings</h2>

            <input
              type="text"
              value={roomName}
              onChange={(e) => setRoomName(e.target.value)}
              className="mb-3 w-full rounded border border-white/10 bg-black/30 px-3 py-2 text-sm text-white placeholder:text-gray-500"
              placeholder="Room name"
            />

            <div className="mb-3">
              <p className="mb-1 text-sm font-medium text-gray-300">
                Trade Room Picture
              </p>
              <label className="inline-flex cursor-pointer items-center rounded-md border border-white/10 bg-white/10 px-3 py-2 text-sm font-medium text-gray-200 transition hover:bg-white/15">
                Choose New Picture
                <input
                  type="file"
                  accept="image/*"
                  className="sr-only"
                  onChange={(e) => {
                    const file = e.target.files?.[0]
                    e.target.value = ""
                    if (file) void handleRoomImageUpload(file)
                  }}
                />
              </label>
            </div>

            <label className="mt-3 flex items-center gap-2 text-sm text-gray-300">
              <input
                type="checkbox"
                checked={showOnProfile}
                onChange={(e) => setShowOnProfile(e.target.checked)}
              />
              Show on my profile
            </label>

            <button
              type="button"
              onClick={() => {
                setMemberSearchQuery("")
                setShowManageMembers(true)
              }}
              className="mt-3 w-full rounded-lg border border-white/10 bg-white/5 py-2 text-sm text-gray-200 hover:bg-white/10"
            >
              Manage Members
            </button>

            <div className="mt-4 border-t border-white/10 pt-4">
              <p className="mb-2 text-sm font-medium text-gray-300">Pages</p>
              <div className="mt-4 space-y-2">
                {sections.map((section) => (
                  <div
                    key={section.id}
                    className="flex items-center justify-between rounded-lg bg-white/5 p-2"
                  >
                    <span className="text-sm text-white">{section.name}</span>

                    <button
                      type="button"
                      disabled={deletingSectionId != null}
                      onClick={() => void promptDeleteSection(section.id)}
                      className="text-red-400 hover:text-red-500 disabled:opacity-50"
                    >
                      {deletingSectionId === section.id ? "…" : "🗑"}
                    </button>
                  </div>
                ))}
              </div>

              <button
                type="button"
                onClick={() => void handleAddSection()}
                className="mt-3 w-full rounded-lg bg-blue-500 py-2 text-sm text-white hover:bg-blue-600"
              >
                + Add Page
              </button>
            </div>

            <div className="mt-4 flex flex-wrap items-center gap-2">
              <button
                type="button"
                onClick={() => void handleRenameRoom({ closeSettings: true })}
                className="rounded bg-green-500/20 px-4 py-2 text-sm text-green-100 hover:bg-green-500/30"
              >
                Save Changes
              </button>

              <button
                type="button"
                disabled={deletingSectionId != null || deleteSectionConfirm != null}
                onClick={() => setShowRoomSettings(false)}
                className="text-sm text-gray-400 hover:text-white disabled:opacity-50"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      ) : null}

      {deleteSectionConfirm ? (
        <div
          className="fixed inset-0 z-[70] flex items-center justify-center bg-black/50 p-4"
          onClick={() => {
            if (deletingSectionId) return
            setDeleteSectionConfirm(null)
          }}
          role="presentation"
        >
          <div
            className="w-full max-w-[320px] rounded-lg border border-white/10 bg-[#0b1f3a] p-5 text-white shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <p className="mb-4 text-sm text-gray-200">
              This channel contains {deleteSectionConfirm.messageCount} message
              {deleteSectionConfirm.messageCount === 1 ? "" : "s"}.
              <br />
              <br />
              Deleting this channel will permanently remove all messages inside
              it.
            </p>
            <div className="flex justify-end gap-3">
              <button
                type="button"
                disabled={deletingSectionId != null}
                onClick={() => setDeleteSectionConfirm(null)}
                className="text-sm text-gray-400 hover:text-white disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                type="button"
                disabled={deletingSectionId != null}
                onClick={() => void handleDeleteSectionConfirm()}
                className="inline-flex items-center gap-1.5 rounded bg-red-500/20 px-3 py-1.5 text-sm text-red-100 hover:bg-red-500/30 disabled:opacity-50"
              >
                {deletingSectionId ? (
                  <>
                    <ActionSpinner />
                    Deleting...
                  </>
                ) : (
                  "Delete Channel"
                )}
              </button>
            </div>
          </div>
        </div>
      ) : null}

      {selectTrade ? (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
          onClick={() => setSelectTrade(false)}
        >
          <div
            className="w-full max-w-md rounded-xl border border-white/10 bg-[#0f172a] p-4 text-white"
            onClick={(e) => e.stopPropagation()}
          >
            <h3 className="text-lg font-semibold mb-3">Send Trade</h3>
            <div className="max-h-80 space-y-2 overflow-y-auto">
              {userTrades.length === 0 ? (
                <p className="text-sm text-gray-400">
                  No public trades available to share.
                </p>
              ) : (
                userTrades.map((trade) => (
                  <button
                    key={trade.id}
                    type="button"
                    onClick={() => void sendTradeMessage(trade)}
                    className="w-full rounded-lg bg-white/5 p-3 text-left hover:bg-white/10"
                  >
                    <p className="text-sm font-medium text-white">
                      {trade.ticker || "Trade"} {trade.direction ? `• ${trade.direction}` : ""}
                    </p>
                    <p className="text-xs text-gray-400">
                      PnL {formatMoneyUnknown(trade.pnl, { empty: "—" })} • RR {formatRR(trade.rr)}
                    </p>
                  </button>
                ))
              )}
            </div>
          </div>
        </div>
      ) : null}
    </>
  )
}

export default function CommunityPage() {
  useEffect(() => {
    const prevRestoration =
      typeof history !== "undefined" ? history.scrollRestoration : undefined
    if (typeof history !== "undefined") {
      history.scrollRestoration = "manual"
    }

    const scrollPageTop = () => {
      window.scrollTo({ top: 0, left: 0, behavior: "auto" })
      document.documentElement.scrollTop = 0
      document.documentElement.scrollLeft = 0
      document.body.scrollTop = 0
      document.body.scrollLeft = 0
    }

    scrollPageTop()
    const raf = requestAnimationFrame(() => {
      scrollPageTop()
    })
    const t = window.setTimeout(scrollPageTop, 100)

    return () => {
      cancelAnimationFrame(raf)
      window.clearTimeout(t)
      if (typeof history !== "undefined" && prevRestoration != null) {
        history.scrollRestoration = prevRestoration
      }
    }
  }, [])

  return (
    <Suspense
      fallback={
        <>
          <Navbar />
          <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-4 text-white md:p-6">
            <SkeletonCommunityPage />
          </div>
        </>
      }
    >
      <CommunityContent />
    </Suspense>
  )
}
