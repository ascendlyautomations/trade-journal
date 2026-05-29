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
import DmStyleComposer from "../components/DmStyleComposer"
import { supabase } from "../../lib/supabaseClient"
import { compressImage } from "@/lib/compressImage"
import { formatEST } from "@/lib/formatEST"
import { isUserPro, reachedMessagesCommentsLimit } from "@/lib/freePlanLimits"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { formatMoneyUnknown, formatRR } from "@/lib/formatDisplay"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"

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
  const [activeMembers, setActiveMembers] = useState<number>(0)
  const [leftMembers, setLeftMembers] = useState<number>(0)
  const [showOnProfile, setShowOnProfile] = useState(true)
  const [roomName, setRoomName] = useState("")
  const [inviteOrigin, setInviteOrigin] = useState("")
  const [roomImage, setRoomImage] = useState<string | null>(null)
  const [inviteTargetRoom, setInviteTargetRoom] = useState<Room | null>(null)
  const [showRoomSettings, setShowRoomSettings] = useState(false)
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
    return selectedRoom.name ? String(selectedRoom.name) : ""
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

  const canPostInRoom = useMemo(() => {
    if (!selectedRoomId || needsJoin) return false
    if (isOwner) return true
    if (sections.length === 0) return true
    return currentSection?.allow_members_chat !== false
  }, [
    selectedRoomId,
    needsJoin,
    isOwner,
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
    if (!selectedRoomId) {
      setActiveMembers(0)
      setLeftMembers(0)
      return
    }

    void loadMemberStats(selectedRoomId)
  }, [selectedRoomId])

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

  async function handleDeleteSection(sectionId: string) {
    if (sections.length <= 1) {
      showPopup({ type: "warning", message: "You must have at least 1 page" })
      return
    }

    const { error } = await supabase
      .from("room_sections")
      .delete()
      .eq("id", sectionId)

    if (error) {
      console.error(error)
      return
    }

    await refetchSections()
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
    }
  }

  async function handleLeaveRoom() {
    const {
      data: { user: authUser },
    } = await supabase.auth.getUser()

    if (!authUser || !selectedRoomId) return

    const { error } = await supabase
      .from("room_members")
      .delete()
      .eq("room_id", selectedRoomId)
      .eq("user_id", authUser.id)

    if (error) {
      console.error("handleLeaveRoom:", error)
      return
    }

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
        router.push("/login")
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
      rooms.find((r) => r.name === decoded || r.name === roomParam)

    if (match) {
      setSelectedRoomId(match.id)
      setInviteTargetRoom(null)
      return
    }

    let cancelled = false

    ;(async () => {
      const { data: slugRow } = await supabase
        .from("rooms")
        .select("id, name, description, slug, image_url, owner_user_id, show_on_profile")
        .eq("slug", decoded)
        .maybeSingle()

      const row =
        slugRow ??
        (
          await supabase
            .from("rooms")
            .select("id, name, description, slug, image_url, owner_user_id, show_on_profile")
            .eq("name", decoded)
            .maybeSingle()
        ).data

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
    if (!user?.id || !selectedRoomId) return
    const content = draft.trim()
    if (!content) return

    const userIsPro = await isUserPro(supabase as any, user.id)
    if (!userIsPro) {
      const limitReached = await reachedMessagesCommentsLimit(
        supabase as any,
        user.id,
        10
      )
      if (limitReached) {
        showPopup({
          type: "warning",
          message: handleSupabaseError({ message: "10 messages limit" }),
        })
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
  }

  async function handleImageUpload(e: ChangeEvent<HTMLInputElement>) {
    if (!user?.id || !selectedRoomId) return
    const file = e.target.files?.[0]
    e.target.value = ""
    if (!file) return

    const userIsPro = await isUserPro(supabase as any, user.id)
    if (!userIsPro) {
      const limitReached = await reachedMessagesCommentsLimit(
        supabase as any,
        user.id,
        10
      )
      if (limitReached) {
        showPopup({
          type: "warning",
          message: handleSupabaseError({ message: "10 messages limit" }),
        })
        return
      }
    }

    let uploadFile: File = file
    if (file.type?.startsWith("image/")) {
      uploadFile = await compressImage(file)
    }
    const filePath = `room-images/${Date.now()}-${uploadFile.name}`

    const { error: uploadError } = await supabase.storage
      .from("screenshots")
      .upload(filePath, uploadFile)

    if (uploadError) {
      console.error("room image upload:", uploadError)
      return
    }

    const { data } = supabase.storage.from("screenshots").getPublicUrl(filePath)

    const { error: insertError } = await supabase.from("room_messages").insert({
      room_id: selectedRoomId,
      user_id: user.id,
      type: "image",
      image_url: data.publicUrl,
      section_id: selectedSectionId,
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
    if (!user?.id || !selectedRoomId) return

    const userIsPro = await isUserPro(supabase as any, user.id)
    if (!userIsPro) {
      const limitReached = await reachedMessagesCommentsLimit(
        supabase as any,
        user.id,
        10
      )
      if (limitReached) {
        showPopup({
          type: "warning",
          message: handleSupabaseError({ message: "10 messages limit" }),
        })
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
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white px-4 py-2">
        <div className="mx-auto flex w-full max-w-6xl flex-col overflow-visible rounded-2xl border border-white/10 bg-black/25 md:h-[calc(100vh-90px)] md:flex-row md:overflow-hidden">
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
                    <p className="px-2 py-3 text-sm text-gray-400">Loading rooms...</p>
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

          <section className="flex min-h-0 w-full min-w-0 flex-col md:flex-1">
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
                      <img
                        key={u.user_id}
                        src={u.profiles?.avatar_url || "/default-avatar.png"}
                        className="h-8 w-8 rounded-full border-2 border-[#0B1120] object-cover"
                        alt=""
                        loading="lazy"
                        decoding="async"
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

                  <input
                    type="file"
                    accept="image/*"
                    className="mb-2 block w-full max-w-xs text-sm text-gray-400 file:mr-2 file:rounded-md file:border-0 file:bg-white/10 file:px-2 file:py-1 file:text-gray-200"
                    onChange={(e) => {
                      const file = e.target.files?.[0]
                      e.target.value = ""
                      if (file) void handleRoomImageUpload(file)
                    }}
                  />

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
                    className="mt-3 text-xs text-gray-400 hover:text-white"
                  >
                    Done setting up
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
                  className="rounded-lg bg-green-500/30 px-6 py-3 text-sm font-medium text-green-100 hover:bg-green-500/40"
                >
                  Join room
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
                            aria-label="Edit channel"
                            onClick={(e) => {
                              e.stopPropagation()
                              setEditingSection(section)
                              setEditSectionName(section.name ?? "")
                              setEditAllowChat(section.allow_members_chat !== false)
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
                <p className="text-sm text-gray-400">Loading messages...</p>
              ) : (
                <>
                  {messages.length === 0 && pinnedMessages.length === 0 ? (
                    <p className="text-sm text-gray-400">No messages yet.</p>
                  ) : null}
                  {messages.length > 0 ? (
                <div className="space-y-3">
                  {messages.map((msg) => (
                    <div key={msg.id} className="rounded-xl bg-white/5 p-3">
                      <div className="mb-1 flex flex-wrap items-center gap-2">
                        <img
                          src={msg.profiles?.avatar_url || "/default-avatar.png"}
                          className="h-6 w-6 shrink-0 rounded-full"
                          alt=""
                          loading="lazy"
                          decoding="async"
                        />
                        <span className="text-sm font-semibold">
                          {msg.profiles?.username || "User"}
                        </span>
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
                        ) : msg.type === "trade" && msg.trades ? (
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
                          <div key={msg.id} className="rounded-lg bg-black/20 p-2">
                            <div className="mb-1 flex items-center justify-between gap-2">
                              <p className="text-xs text-gray-400">
                                {msg.profiles?.username || "User"}
                              </p>
                              {isOwner ? (
                                <button
                                  type="button"
                                  onClick={() =>
                                    void handleTogglePin(msg.id, msg.pinned)
                                  }
                                  className={`shrink-0 text-xs ${
                                    msg.pinned ? "text-yellow-400" : "text-gray-400"
                                  }`}
                                >
                                  📌
                                </button>
                              ) : null}
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
                    Only the room owner can post in this section.
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
                    sendDisabled={!canPostInRoom || !draft.trim()}
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
          onClick={() => setEditingSection(null)}
          role="presentation"
        >
          <div
            className="w-[350px] rounded-lg bg-[#0b1f3a] p-6 text-white shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="mb-3 text-lg font-semibold">Edit Channel</h2>

            <input
              type="text"
              value={editSectionName}
              onChange={(e) => setEditSectionName(e.target.value)}
              className="mb-3 w-full rounded border border-white/10 bg-black/30 px-3 py-2 text-sm text-white placeholder:text-gray-500"
              placeholder="Channel name"
            />

            <label className="mb-4 flex cursor-pointer items-center gap-2 text-sm text-gray-300">
              <input
                type="checkbox"
                className="rounded border-white/20 bg-black/30"
                checked={editAllowChat}
                onChange={(e) => setEditAllowChat(e.target.checked)}
              />
              Allow members to chat
            </label>

            <div className="flex justify-end gap-3">
              <button
                type="button"
                onClick={() => setEditingSection(null)}
                className="text-sm text-gray-400 hover:text-white"
              >
                Cancel
              </button>

              <button
                type="button"
                onClick={() => void handleSaveSectionEdit()}
                className="rounded bg-green-500/20 px-4 py-2 text-sm text-green-100 hover:bg-green-500/30"
              >
                Save
              </button>
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

      {showRoomSettings && isOwner && selectedRoomId ? (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
          onClick={() => setShowRoomSettings(false)}
          role="presentation"
        >
          <div
            className="w-full max-w-[400px] rounded-lg bg-[#0b1f3a] p-6 text-white shadow-xl"
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

            <input
              type="file"
              accept="image/*"
              className="mb-3 block w-full text-sm text-gray-400 file:mr-2 file:rounded-md file:border-0 file:bg-white/10 file:px-2 file:py-1 file:text-gray-200"
              onChange={(e) => {
                const file = e.target.files?.[0]
                e.target.value = ""
                if (file) void handleRoomImageUpload(file)
              }}
            />

            <label className="mt-3 flex items-center gap-2 text-sm text-gray-300">
              <input
                type="checkbox"
                checked={showOnProfile}
                onChange={(e) => setShowOnProfile(e.target.checked)}
              />
              Show on my profile
            </label>

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
                      onClick={() => void handleDeleteSection(section.id)}
                      className="text-red-400 hover:text-red-500"
                    >
                      🗑
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
                onClick={() => setShowRoomSettings(false)}
                className="text-sm text-gray-400 hover:text-white"
              >
                Close
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
                <p className="text-sm text-gray-400">No trades available.</p>
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
    <Suspense fallback={<div>Loading...</div>}>
      <CommunityContent />
    </Suspense>
  )
}
