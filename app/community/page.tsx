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

type Room = {
  id: string
  name?: string | null
  description?: string | null
}

type RoomMessage = {
  id: string
  room_id: string
  user_id: string
  type?: string | null
  trade_id?: string | null
  content: string
  image_url?: string | null
  created_at: string
  trades?: {
    id?: string
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

function formatLocalTime(value: string) {
  const d = new Date(value)
  if (Number.isNaN(d.getTime())) return ""
  return d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })
}

function tradeImageSrc(imageUrl: string | null | undefined): string | null {
  const raw = imageUrl != null ? String(imageUrl).trim() : ""
  if (!raw) return null
  if (raw.startsWith("http")) return raw
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return null
  return `${base}/storage/v1/object/public/screenshots/${raw}`
}

function CommunityContent() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const roomParam = searchParams.get("room")
  const [user, setUser] = useState<any>(null)
  const [username, setUsername] = useState("User")
  const [rooms, setRooms] = useState<Room[]>([])
  const [selectedRoomId, setSelectedRoomId] = useState<string | null>(null)
  const [messages, setMessages] = useState<RoomMessage[]>([])
  const [loadingRooms, setLoadingRooms] = useState(true)
  const [loadingMessages, setLoadingMessages] = useState(false)
  const [draft, setDraft] = useState("")
  const [activeUsers, setActiveUsers] = useState<ActivePresence[]>([])
  const [typingUsers, setTypingUsers] = useState<string[]>([])
  const [selectTrade, setSelectTrade] = useState(false)
  const [userTrades, setUserTrades] = useState<any[]>([])
  const [mobileRoomsOpen, setMobileRoomsOpen] = useState(false)
  const typingChannelRef = useRef<any>(null)
  const messagesScrollRef = useRef<HTMLDivElement | null>(null)

  const selectedRoom = useMemo(
    () => rooms.find((r) => r.id === selectedRoomId) ?? null,
    [rooms, selectedRoomId]
  )

  const loadMessages = useCallback(async (roomId: string) => {
    setLoadingMessages(true)
    const { data, error } = await supabase
      .from("room_messages")
      .select(
        `
        *,
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
      .eq("room_id", roomId)
      .order("created_at", { ascending: true })

    if (error) {
      console.error(
        "room_messages fetch FULL:",
        JSON.stringify(error, null, 2)
      )
      setMessages([])
      setLoadingMessages(false)
      return
    }

    setMessages((data || []) as RoomMessage[])
    setLoadingMessages(false)
  }, [])

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

      const { data, error } = await supabase
        .from("rooms")
        .select("id, name, description")
        .order("name", { ascending: true })

      if (error) {
        console.error("rooms fetch:", error)
        setRooms([])
        setLoadingRooms(false)
        return
      }

      const nextRooms = (data ?? []) as Room[]
      setRooms(nextRooms)
      setLoadingRooms(false)
      if (nextRooms.length > 0) {
        setSelectedRoomId(nextRooms[0].id)
      }
    }

    void init()
  }, [router])

  useEffect(() => {
    if (!roomParam || rooms.length === 0) return
    const match = rooms.find((r) => r.name === roomParam)
    if (match) setSelectedRoomId(match.id)
  }, [roomParam, rooms])

  useEffect(() => {
    if (!selectedRoomId) {
      setMessages([])
      setActiveUsers([])
      return
    }
    void loadMessages(selectedRoomId)
  }, [selectedRoomId, loadMessages])

  useEffect(() => {
    if (!selectedRoomId || !user?.id) {
      setActiveUsers([])
      return
    }

    let cancelled = false

    const updatePresenceAndCount = async () => {
      const payload = {
        room_id: selectedRoom?.id,
        user_id: user?.id,
        last_seen: new Date().toISOString(),
      }

      console.log("Presence payload:", payload)

      // Prevent invalid calls
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
        .eq("room_id", selectedRoomId)
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
  }, [selectedRoomId, user?.id])

  useEffect(() => {
    if (!selectedRoomId) return

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

        setMessages((prev) => {
          if (prev.some((m) => m.id === data.id)) return prev
          return [...prev, data as RoomMessage]
        })
      }
    )
    channel.subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, [selectedRoomId])

  useEffect(() => {
    if (!selectedRoomId || !user?.id) {
      setTypingUsers([])
      return
    }

    const channel = supabase.channel(`typing-room-${selectedRoomId}`)
    typingChannelRef.current = channel

    channel.on("broadcast", { event: "typing" }, (payload: any) => {
      const typingUser = payload?.payload?.user
      if (!typingUser || typingUser === username) return

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
  }, [selectedRoomId, user?.id, username])

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

    const { error } = await supabase.from("room_messages").insert({
      room_id: selectedRoomId,
      user_id: user.id,
      content,
    })
    if (error) {
      console.error("room_messages insert:", error)
      return
    }

    setDraft("")
  }

  async function handleImageUpload(e: ChangeEvent<HTMLInputElement>) {
    if (!user?.id || !selectedRoomId) return
    const file = e.target.files?.[0]
    e.target.value = ""
    if (!file) return

    const filePath = `room-images/${Date.now()}-${file.name}`

    const { error: uploadError } = await supabase.storage
      .from("screenshots")
      .upload(filePath, file)

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
    })

    if (insertError) {
      console.error("room image message insert:", insertError)
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

    const { error } = await supabase.from("room_messages").insert({
      room_id: selectedRoomId,
      user_id: user.id,
      type: "trade",
      trade_id: trade.id,
      content: "Shared a trade",
    })

    if (error) {
      console.error("room trade message insert:", error)
      return
    }

    setSelectTrade(false)
  }

  return (
    <>
      <Navbar />
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
                    rooms.map((room) => {
                      const selected = room.id === selectedRoomId
                      return (
                        <button
                          key={room.id}
                          type="button"
                          onClick={() => {
                            setSelectedRoomId(room.id)
                            setMobileRoomsOpen(false)
                          }}
                          className={`mb-1 flex min-h-[44px] w-full items-center rounded-lg px-3 py-2 text-left text-sm transition ${
                            selected
                              ? "bg-blue-500/25 text-blue-100"
                              : "text-gray-200 hover:bg-white/10"
                          }`}
                        >
                          <div className="flex min-w-0 items-center gap-2">
                            <span className="truncate">{room.name || "Room"}</span>
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
              <h2 className="text-base font-medium">
                {selectedRoom?.name || "Select a room"}
              </h2>
              {selectedRoomId ? (
                <div className="mt-1 flex items-center">
                  <div className="flex items-center space-x-[-8px]">
                    {activeUsers.slice(0, 5).map((u) => (
                      <img
                        key={u.user_id}
                        src={u.profiles?.avatar_url || "/default-avatar.png"}
                        className="h-8 w-8 rounded-full border-2 border-[#0B1120] object-cover"
                        alt=""
                      />
                    ))}
                  </div>
                  <span className="ml-2 text-sm text-gray-400">
                    {activeUsers.length} active traders
                  </span>
                </div>
              ) : null}
            </div>

            <div
              ref={messagesScrollRef}
              className="min-h-0 max-h-[min(65svh,525px)] overflow-y-auto px-4 py-3 md:max-h-none md:flex-1"
            >
              {!selectedRoomId ? (
                <p className="text-sm text-gray-400">Pick a room to start chatting.</p>
              ) : loadingMessages ? (
                <p className="text-sm text-gray-400">Loading messages...</p>
              ) : messages.length === 0 ? (
                <p className="text-sm text-gray-400">No messages yet.</p>
              ) : (
                <div className="space-y-3">
                  {messages.map((msg) => (
                    <div key={msg.id} className="rounded-xl bg-white/5 p-3">
                      <div className="flex items-center gap-2 mb-1">
                        <img
                          src={msg.profiles?.avatar_url || "/default-avatar.png"}
                          className="w-6 h-6 rounded-full"
                          alt=""
                        />
                        <span className="text-sm font-semibold">
                          {msg.profiles?.username || "User"}
                        </span>
                        <span className="text-xs text-gray-400">
                          {formatLocalTime(msg.created_at)}
                        </span>
                      </div>

                      <div className="text-sm">
                        {msg.type === "image" ? (
                          <img
                            src={msg.image_url || ""}
                            className="rounded max-w-xs mt-1"
                            alt=""
                          />
                        ) : msg.type === "trade" && msg.trades ? (
                          <div className="bg-white/5 p-2 rounded mt-1 max-w-xs">
                            {tradeImageSrc(msg.trades.image_url) ? (
                              <img
                                src={tradeImageSrc(msg.trades.image_url) || ""}
                                className="rounded"
                                alt=""
                              />
                            ) : null}
                            <p className="text-xs mt-1">
                              PnL: {msg.trades.pnl ?? "—"} | RR: {msg.trades.rr ?? "—"}
                            </p>
                          </div>
                        ) : (
                          <p className="break-words text-sm text-white">{msg.content}</p>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            <DmStyleComposer
              value={draft}
              onChange={(v) => {
                setDraft(v)
                sendTyping()
              }}
              onSend={() => void sendMessage()}
              placeholder={
                selectedRoomId ? "Message room..." : "Select a room first"
              }
              textDisabled={!selectedRoomId}
              sendDisabled={!selectedRoomId || !draft.trim()}
              onImageChange={(e) => void handleImageUpload(e)}
              imageDisabled={!selectedRoomId}
              onTradeClick={() => setSelectTrade(true)}
              tradeDisabled={!selectedRoomId}
              beforeRow={
                typingUsers.length > 0 ? (
                  <p className="text-xs text-gray-400">
                    {typingUsers.join(", ")} typing...
                  </p>
                ) : null
              }
            />
          </section>
        </div>
      </div>

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
                      PnL {trade.pnl != null && trade.pnl !== "" ? `$${trade.pnl}` : "—"} • RR{" "}
                      {trade.rr ?? "—"}
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
