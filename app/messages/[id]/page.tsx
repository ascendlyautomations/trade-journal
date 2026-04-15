"use client"

import Navbar from "../../components/Navbar"
import TradeSocialLayer from "../../components/TradeSocialLayer"
import { useEffect, useState, useRef, type ChangeEvent } from "react"
import { supabase } from "../../../lib/supabaseClient"
import { useParams, useRouter } from "next/navigation"

function tradeScreenshotSrc(url: string | null | undefined): string | null {
  const raw = url != null ? String(url).trim() : ""
  if (!raw) return null
  if (raw.startsWith("http")) return raw
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return null
  return `${base}/storage/v1/object/public/screenshots/${raw}`
}

function postScreenshotSrc(url: string | null | undefined): string | null {
  const raw = url != null ? String(url).trim() : ""
  if (!raw) return null
  if (raw.startsWith("http")) return raw
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return null
  return `${base}/storage/v1/object/public/screenshots/${raw}`
}

function getTradeStageRaw(trade: any): string {
  const v =
    trade?.account_status ??
    trade?.account_stage ??
    trade?.account_category ??
    trade?.trade_type ??
    ""
  return String(v).trim()
}

function TradeMessageBubble({
  message,
  isMe,
  userId,
  activeMenuId,
  setActiveMenuId,
  deleteForMe,
  deleteForEveryone,
  onOpenTrade,
}: {
  message: any
  isMe: boolean
  userId: string | undefined
  activeMenuId: string | null
  setActiveMenuId: (id: string | null) => void
  deleteForMe: (m: any) => void
  deleteForEveryone: (m: any) => void
  onOpenTrade: (trade: any) => void
}) {
  const [trade, setTrade] = useState<any>(null)

  useEffect(() => {
    if (!message.trade_id) return
    let cancelled = false
    ;(async () => {
      const { data } = await supabase
        .from("trades")
        .select("*")
        .eq("id", message.trade_id)
        .maybeSingle()
      if (!cancelled && data) {
        console.log("TRADE DATA:", data)
        setTrade(data)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [message.trade_id])

  const imgSrc = trade ? tradeScreenshotSrc(trade.image_url) : null
  const pnlNum = trade != null ? Number(trade.pnl) : NaN
  const pnlNonNeg = !Number.isNaN(pnlNum) && pnlNum >= 0
  const stageRaw = trade ? getTradeStageRaw(trade) : ""
  const stageKey = stageRaw.toLowerCase()
  const stageFooterText = stageRaw || "Trade"

  if (message.deleted_for_everyone) {
    return (
      <div className={`flex ${isMe ? "justify-end" : "justify-start"}`}>
        <p className="text-gray-400 italic text-sm">Message deleted</p>
      </div>
    )
  }

  if (!trade) {
    return (
      <div className={`flex ${isMe ? "justify-end" : "justify-start"}`}>
        <div className="max-w-xs rounded-lg bg-[#1e293b] p-3 text-sm text-gray-400">
          Loading trade…
        </div>
      </div>
    )
  }

  const isMine = message.sender_id === userId

  const menuOpen = activeMenuId === message.id

  return (
    <div className={`flex ${isMe ? "justify-end" : "justify-start"}`}>
      <div className="relative group inline-block max-w-[75%] overflow-visible">
        <button
          type="button"
          onClick={(e) => {
            e.stopPropagation()
            setActiveMenuId(menuOpen ? null : message.id)
          }}
          className={`absolute top-1 right-1 z-10 rounded px-1.5 py-0.5 text-xs text-gray-400 transition-opacity duration-200 hover:text-gray-200 ${
            menuOpen ? "opacity-100" : "opacity-0 group-hover:opacity-100"
          }`}
          aria-label="Message actions"
        >
          ⋯
        </button>

        {menuOpen ? (
          <div
            className={`absolute top-7 z-50 w-40 rounded-lg border border-gray-600 bg-[#1e293b] shadow-lg ${
              isMine ? "right-1" : "left-1"
            }`}
          >
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation()
                deleteForMe(message)
              }}
              className="w-full px-3 py-2 text-left text-sm hover:bg-white/10"
            >
              Delete for me
            </button>
            {message.sender_id === userId ? (
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation()
                  deleteForEveryone(message)
                }}
                className="w-full px-3 py-2 text-left text-sm hover:bg-white/10"
              >
                Delete for everyone
              </button>
            ) : null}
          </div>
        ) : null}

        <div
          role="button"
          tabIndex={0}
          onClick={() => onOpenTrade(trade)}
          onKeyDown={(e) => {
            if (e.key === "Enter" || e.key === " ") {
              e.preventDefault()
              onOpenTrade(trade)
            }
          }}
          className="cursor-pointer bg-gradient-to-br from-[#0f172a] to-[#1e293b] border border-gray-700 rounded-xl p-4 shadow-lg transition hover:scale-[1.02] hover:shadow-xl"
        >
          <div className="mb-2 flex items-center justify-between">
            <div>
              <p className="text-lg font-semibold text-white">
                {trade.ticker}
              </p>
              <p className="text-xs text-gray-400">{trade.direction}</p>
            </div>

            <div
              className={`text-sm font-semibold ${
                pnlNonNeg ? "text-green-400" : "text-red-400"
              }`}
            >
              {Number.isNaN(pnlNum)
                ? `$${trade.pnl}`
                : `${pnlNonNeg ? "+" : "-"}$${Math.abs(pnlNum)}`}
            </div>
          </div>

          <div className="mb-3 flex justify-between text-xs text-gray-400">
            <span>RR: {trade.rr}</span>
            <span>Points: {trade.points ?? "—"}</span>
          </div>

          {trade.public_description && (
            <p className="text-gray-300 text-sm mt-2">
              {trade.public_description}
            </p>
          )}

          {imgSrc ? (
            <img
              src={imgSrc}
              alt=""
              className="mb-3 h-32 w-full rounded-lg border border-gray-700 object-cover"
            />
          ) : null}

          <div className="flex items-center justify-between text-xs">
            <span
              className={`px-2 py-1 rounded-md text-xs font-medium ${
                stageKey === "live"
                  ? "bg-green-500/20 text-green-400"
                  : stageKey === "funded"
                    ? "bg-blue-500/20 text-blue-400"
                    : stageKey === "eval"
                      ? "bg-yellow-500/20 text-yellow-400"
                      : "bg-gray-500/20 text-gray-400"
              }`}
            >
              {stageFooterText}
            </span>

            <span className="text-gray-500">Shared Trade</span>
          </div>
        </div>

        <div className="mt-3 max-w-full" onClick={(e) => e.stopPropagation()}>
          <TradeSocialLayer
            tradeId={trade.id}
            currentUserId={userId}
            tradeOwnerUserId={trade.user_id}
          />
        </div>
      </div>
    </div>
  )
}

function PostMessageBubble({
  message,
  isMe,
  userId,
  activeMenuId,
  setActiveMenuId,
  deleteForMe,
  deleteForEveryone,
  onOpenPost,
}: {
  message: any
  isMe: boolean
  userId: string | undefined
  activeMenuId: string | null
  setActiveMenuId: (id: string | null) => void
  deleteForMe: (m: any) => void
  deleteForEveryone: (m: any) => void
  onOpenPost: (post: any) => void
}) {
  const [post, setPost] = useState<any>(null)

  useEffect(() => {
    if (!message.post_id) return
    let cancelled = false
    ;(async () => {
      const { data } = await supabase
        .from("posts")
        .select("*, profiles(username, avatar_url)")
        .eq("id", message.post_id)
        .maybeSingle()
      if (!cancelled && data) {
        setPost(data)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [message.post_id])

  if (message.deleted_for_everyone) {
    return (
      <div className={`flex ${isMe ? "justify-end" : "justify-start"}`}>
        <p className="text-gray-400 italic text-sm">Message deleted</p>
      </div>
    )
  }

  if (!post) {
    return (
      <div className={`flex ${isMe ? "justify-end" : "justify-start"}`}>
        <div className="max-w-xs rounded-lg bg-[#1e293b] p-3 text-sm text-gray-400">
          Loading post...
        </div>
      </div>
    )
  }

  const menuOpen = activeMenuId === message.id
  const imageSrc = postScreenshotSrc(post.image_url)
  const pnl = Number(post.pnl)
  const isWin = !Number.isNaN(pnl) && pnl >= 0

  return (
    <div className={`flex ${isMe ? "justify-end" : "justify-start"}`}>
      <div className="relative group inline-block max-w-[75%] overflow-visible">
        <button
          type="button"
          onClick={(e) => {
            e.stopPropagation()
            setActiveMenuId(menuOpen ? null : message.id)
          }}
          className={`absolute top-1 right-1 z-10 rounded px-1.5 py-0.5 text-xs text-gray-400 transition-opacity duration-200 hover:text-gray-200 ${
            menuOpen ? "opacity-100" : "opacity-0 group-hover:opacity-100"
          }`}
          aria-label="Message actions"
        >
          ⋯
        </button>

        {menuOpen ? (
          <div
            className={`absolute top-7 z-50 w-40 rounded-lg border border-gray-600 bg-[#1e293b] shadow-lg ${
              isMe ? "right-1" : "left-1"
            }`}
          >
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation()
                deleteForMe(message)
              }}
              className="w-full px-3 py-2 text-left text-sm hover:bg-white/10"
            >
              Delete for me
            </button>
            {message.sender_id === userId ? (
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation()
                  deleteForEveryone(message)
                }}
                className="w-full px-3 py-2 text-left text-sm hover:bg-white/10"
              >
                Delete for everyone
              </button>
            ) : null}
          </div>
        ) : null}

        <div
          role="button"
          tabIndex={0}
          onClick={() => onOpenPost(post)}
          onKeyDown={(e) => {
            if (e.key === "Enter" || e.key === " ") {
              e.preventDefault()
              onOpenPost(post)
            }
          }}
          className="cursor-pointer bg-gradient-to-br from-[#0f172a] to-[#1e293b] border border-gray-700 rounded-xl p-4 shadow-lg transition hover:scale-[1.02] hover:shadow-xl"
        >
          {message.content ? (
            <p className="text-sm text-gray-300 mb-2">{message.content}</p>
          ) : null}

          <div className="mb-2 flex items-center justify-between">
            <p className="text-sm font-semibold text-white">
              @{post.profiles?.username || "User"}
            </p>
            <span className="text-xs text-gray-400">Shared Post</span>
          </div>

          {imageSrc ? (
            <img
              src={imageSrc}
              alt=""
              className="mb-3 h-32 w-full rounded-lg border border-gray-700 object-cover"
            />
          ) : null}

          <div className="flex justify-between text-xs">
            <span className={isWin ? "text-emerald-400" : "text-red-400"}>
              {Number.isNaN(pnl) ? "—" : `${isWin ? "+" : ""}$${pnl}`}
            </span>
            <span className="text-gray-400">
              RR {post.rr != null && post.rr !== "" ? post.rr : "—"}
            </span>
          </div>
        </div>
      </div>
    </div>
  )
}

export default function DMPage() {
  const params = useParams()
  const router = useRouter()
  const id = params.id as string
  const activeConversationId = id

  const [messages, setMessages] = useState<any[]>([])
  const [input, setInput] = useState("")
  const [user, setUser] = useState<any>(null)
  const [selectedFile, setSelectedFile] = useState<File | null>(null)
  const [selectedImage, setSelectedImage] = useState<File | null>(null)
  const [previewUrl, setPreviewUrl] = useState<string | null>(null)
  const [otherUser, setOtherUser] = useState<any>(null)
  const [conversation, setConversation] = useState<any>(null)
  const [participants, setParticipants] = useState<any[]>([])
  const [activeMenuId, setActiveMenuId] = useState<string | null>(null)
  const [isTyping, setIsTyping] = useState(false)
  const [typingUsers, setTypingUsers] = useState<string[]>([])
  const [showGroupSettings, setShowGroupSettings] = useState(false)
  const [groupName, setGroupName] = useState("")
  const [groupImage, setGroupImage] = useState<File | null>(null)
  const [savingGroupSettings, setSavingGroupSettings] = useState(false)
  const [groupSettingsSuccess, setGroupSettingsSuccess] = useState("")
  const [showAddMembers, setShowAddMembers] = useState(false)
  const [allUsers, setAllUsers] = useState<any[]>([])
  const [selectedUsers, setSelectedUsers] = useState<any[]>([])
  const [showTradePicker, setShowTradePicker] = useState(false)
  const [trades, setTrades] = useState<any[]>([])
  const [tradeModalTrade, setTradeModalTrade] = useState<any>(null)
  const [postModalPost, setPostModalPost] = useState<any>(null)

  const scrollRef = useRef<HTMLDivElement>(null)
  const fileRef = useRef<HTMLInputElement>(null)
  const userIdRef = useRef<string | null>(null)

  useEffect(() => {
    userIdRef.current = user?.id ?? null
  }, [user?.id])

  function openTradeModal(trade: any) {
    setTradeModalTrade(trade)
  }

  function openPostModal(post: any) {
    setPostModalPost(post)
  }

  useEffect(() => {
    init()
  }, [id])

  useEffect(() => {
    if (!activeConversationId) return

    const topic = `messages-${activeConversationId}`
    supabase.getChannels().forEach((c) => {
      if (c.topic === topic) {
        supabase.removeChannel(c)
      }
    })

    const channel = supabase.channel(topic)

    channel.on(
      "postgres_changes",
      {
        event: "*",
        schema: "public",
        table: "messages",
        filter: `conversation_id=eq.${activeConversationId}`
      },
      (payload) => {
        console.log("Realtime event:", payload)

        if (payload.eventType === "INSERT") {
          const raw = payload.new as { id?: string; sender_id?: string }
          void (async () => {
            let row: any = raw
            if (raw.id) {
              const { data } = await supabase
                .from("messages")
                .select(
                  `
                  *,
                  profiles!sender_id (
                    username,
                    avatar_url
                  )
                `
                )
                .eq("id", raw.id)
                .maybeSingle()
              if (data) row = data
            }
            setMessages((prev) => {
              const without = prev.filter((x) => x.id !== raw.id)
              const updated = [...without, row]
              return updated.sort(
                (a, b) =>
                  new Date(a.created_at).getTime() -
                  new Date(b.created_at).getTime()
              )
            })

            const uid = userIdRef.current
            const senderId = raw.sender_id
            if (uid && senderId && senderId !== uid) {
              void markMessagesSeen(uid)
            }
          })()
        }

        if (payload.eventType === "UPDATE") {
          setMessages((prev) =>
            prev.map((msg) => {
              if (msg.id !== (payload.new as { id: string }).id) return msg
              const next = payload.new as any
              return {
                ...next,
                profiles: next.profiles ?? msg.profiles,
              }
            })
          )
        }
      }
    )

    channel.subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, [activeConversationId])

  useEffect(() => {
    scrollToBottom()
  }, [messages])

  useEffect(() => {
    if (!isTyping) return
    const timer = setTimeout(() => setIsTyping(false), 1200)
    return () => clearTimeout(timer)
  }, [isTyping, input])

  useEffect(() => {
    const el = document.getElementById("chat-bottom")
    el?.scrollIntoView({ behavior: "smooth" })
  }, [messages])

  useEffect(() => {
    setGroupName(conversation?.name || "")
  }, [conversation?.name])

  useEffect(() => {
    if (!showAddMembers) return

    setSelectedUsers([])

    const fetchUsers = async () => {
      const { data } = await supabase
        .from("profiles")
        .select("id, username, avatar_url")

      setAllUsers(data || [])
    }

    fetchUsers()
  }, [showAddMembers])

  useEffect(() => {
    if (!showTradePicker || !user?.id) return

    const fetchTrades = async () => {
      const { data } = await supabase
        .from("trades")
        .select("*")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false })

      setTrades(data || [])
    }

    fetchTrades()
  }, [showTradePicker, user?.id])

  async function init() {
    const {
      data: { user }
    } = await supabase.auth.getUser()

    setUser(user)

    if (user) {
      await fetchConversationDetails(user.id)
      await loadMessages(user.id)
    }
  }

  async function fetchConversationDetails(currentUserId: string) {
    const { data: convo } = await supabase
      .from("conversations")
      .select("id, is_group, name, avatar_url")
      .eq("id", id)
      .maybeSingle()

    setConversation(convo || null)

    const { data } = await supabase
      .from("conversation_participants")
      .select(`
        user_id,
        profiles (id, username, avatar_url)
      `)
      .eq("conversation_id", id)

    setParticipants(data || [])

    const other = data?.find((u: any) => u.user_id !== currentUserId)

    setOtherUser(other?.profiles || null)
  }

  function scrollToBottom() {
    setTimeout(() => {
      if (scrollRef.current) {
        scrollRef.current.scrollTop = scrollRef.current.scrollHeight
      }
    }, 50)
  }

  async function loadMessages(currentUserId: string) {
    const { data: fetched } = await supabase
      .from("messages")
      .select(
        `
        *,
        profiles!sender_id (
          username,
          avatar_url
        )
      `
      )
      .eq("conversation_id", id)
      .order("created_at", { ascending: true })

    const { data: deleted } = await supabase
      .from("message_deletions")
      .select("message_id")
      .eq("user_id", currentUserId)

    const filteredMessages = (fetched || []).filter((msg) => {
      if (msg.deleted_for_everyone) return true
      return !(deleted || []).some((d) => d.message_id === msg.id)
    })

    setMessages(
      (filteredMessages || []).sort(
        (a, b) =>
          new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
      )
    )
  }

  async function markMessagesSeen(currentUserId: string) {
    const { data } = await supabase
      .from("messages")
      .select("id, seen_by, sender_id")
      .eq("conversation_id", id)

    for (const msg of data || []) {
      if (!msg.sender_id) continue
      if (msg.sender_id === currentUserId) continue
      const seenBy = Array.isArray(msg.seen_by) ? msg.seen_by : []
      if (seenBy.includes(currentUserId)) continue
      await supabase
        .from("messages")
        .update({ seen_by: [...seenBy, currentUserId] })
        .eq("id", msg.id)
    }
  }

  useEffect(() => {
    if (!user?.id || !id) return
    void markMessagesSeen(user.id)
  }, [id, user?.id])

  function removeImage() {
    setSelectedFile(null)
    setSelectedImage(null)
    setPreviewUrl(null)
    if (fileRef.current) fileRef.current.value = ""
  }

  function handleImageChange(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return

    setSelectedImage(file)
    setSelectedFile(file)
    setPreviewUrl(URL.createObjectURL(file))
  }

  async function handleFileChange(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file || !conversation?.id) return

    setGroupImage(file)

    const fileExt = file.name.split(".").pop()
    const fileName = `${conversation.id}-${Date.now()}.${fileExt}`
    const filePath = `${fileName}`

    const { error: uploadError } = await supabase.storage
      .from("group-avatars")
      .upload(filePath, file, {
        cacheControl: "3600",
        upsert: true
      })

    if (uploadError) {
      console.error("Upload error:", uploadError)
      return
    }

    const { data: publicUrlData } = supabase.storage
      .from("group-avatars")
      .getPublicUrl(filePath)

    const publicUrl = publicUrlData.publicUrl

    await supabase
      .from("conversations")
      .update({
        avatar_url: publicUrl
      })
      .eq("id", conversation.id)

    if (conversation.avatar_url !== publicUrl) {
      setConversation((prev: any) => ({
        ...prev,
        avatar_url: publicUrl
      }))
    }
    console.log("Saved avatar URL:", publicUrl)
  }

  async function sendMessage() {
    if (!user) return
    if (!input.trim() && !selectedFile) return

    let imageUrl = null

    if (selectedFile) {
      const fileName = `${Date.now()}-${selectedFile.name}`

      await supabase.storage
        .from("screenshots")
        .upload(fileName, selectedFile)

      imageUrl = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/screenshots/${fileName}`
    }

    await supabase.from("messages").insert({
      conversation_id: id,
      sender_id: user.id,
      content: input || "",
      image_url: imageUrl,
    })

    const lastMsg = input || (imageUrl ? "Image" : "")
    const lastMessageAt = new Date().toISOString()

    await supabase
      .from("conversations")
      .update({
        last_message: lastMsg,
        last_message_at: lastMessageAt
      })
      .eq("id", id)

    if (typeof window !== "undefined") {
      window.dispatchEvent(
        new CustomEvent("tj-conversation-updated", {
          detail: {
            conversationId: id,
            last_message: lastMsg,
            last_message_at: lastMessageAt
          }
        })
      )
    }

    setInput("")
    setSelectedFile(null)
    setSelectedImage(null)
    setPreviewUrl(null)
    if (fileRef.current) fileRef.current.value = ""
    setIsTyping(false)
  }

  async function handleSendTrade(trade: any) {
    if (!user) return

    await supabase.from("messages").insert({
      conversation_id: activeConversationId,
      sender_id: user.id,
      type: "trade",
      trade_id: trade.id,
      content: "Shared a trade",
    })

    const lastMsg = "Shared a trade"
    const lastMessageAt = new Date().toISOString()

    await supabase
      .from("conversations")
      .update({
        last_message: lastMsg,
        last_message_at: lastMessageAt,
      })
      .eq("id", id)

    if (typeof window !== "undefined") {
      window.dispatchEvent(
        new CustomEvent("tj-conversation-updated", {
          detail: {
            conversationId: id,
            last_message: lastMsg,
            last_message_at: lastMessageAt,
          },
        })
      )
    }

    setShowTradePicker(false)
  }

  async function saveGroupSettings() {
    if (!conversation?.id || !conversation?.is_group) return
    setSavingGroupSettings(true)
    setGroupSettingsSuccess("")

    const trimmedName = groupName.trim()
    if (trimmedName) {
      const { error: nameError } = await supabase
        .from("conversations")
        .update({
          name: trimmedName
        })
        .eq("id", conversation.id)

      if (!nameError) {
        setConversation((prev: any) => ({
          ...prev,
          name: trimmedName
        }))
      }
    }

    setSavingGroupSettings(false)
    setGroupImage(null)
    setGroupSettingsSuccess("Saved")
    setShowGroupSettings(false)
  }

  async function deleteForMe(message: any) {
    if (!user) return
    await supabase.from("message_deletions").insert({
      message_id: message.id,
      user_id: user.id
    })
    setMessages((prev) => prev.filter((m) => m.id !== message.id))
    setActiveMenuId(null)
  }

  function toggleUser(profileUser: any) {
    setSelectedUsers((prev) =>
      prev.some((u) => u.id === profileUser.id)
        ? prev.filter((u) => u.id !== profileUser.id)
        : [...prev, profileUser]
    )
  }

  async function handleAddUsers() {
    if (!user || !conversation?.id || selectedUsers.length === 0) return

    const toAdd = [...selectedUsers]
    const inserts = toAdd.map((u) => ({
      conversation_id: conversation.id,
      user_id: u.id,
    }))

    await supabase.from("conversation_participants").insert(inserts)

    const meRow = participants.find((p: any) => p.user_id === user.id)
    const rawProf = meRow?.profiles
    const prof = Array.isArray(rawProf) ? rawProf[0] : rawProf
    const actorName = prof?.username || "Someone"

    await supabase.from("messages").insert({
      conversation_id: conversation.id,
      content: `${actorName} added ${toAdd.map((u) => u.username).join(", ")}`,
      sender_id: null,
      is_system: true,
    })

    setParticipants((prev) => [
      ...prev,
      ...toAdd.map((u) => ({
        user_id: u.id,
        profiles: u,
      })),
    ])

    setShowAddMembers(false)
    setSelectedUsers([])
  }

  async function handleLeaveGroup() {
    if (!user || !conversation?.id || !conversation?.is_group) return

    const meRow = participants.find((p: any) => p.user_id === user.id)
    const rawProf = meRow?.profiles
    const prof = Array.isArray(rawProf) ? rawProf[0] : rawProf
    const displayName = prof?.username || "Someone"

    await supabase
      .from("conversation_participants")
      .delete()
      .eq("conversation_id", conversation.id)
      .eq("user_id", user.id)

    await supabase.from("messages").insert({
      conversation_id: conversation.id,
      content: `${displayName} left the group`,
      sender_id: null,
      is_system: true,
    })

    setShowGroupSettings(false)
    router.push("/messages")
  }

  async function deleteForEveryone(message: any) {
    if (!user || message.sender_id !== user.id) return
    await supabase
      .from("messages")
      .update({ deleted_for_everyone: true })
      .eq("id", message.id)
    setMessages((prev) =>
      prev.map((m) =>
        m.id === message.id ? { ...m, deleted_for_everyone: true } : m
      )
    )
    setActiveMenuId(null)
  }

  const title = conversation?.is_group
    ? conversation?.name || "Group Chat"
    : otherUser?.username
      ? `@${otherUser.username}`
      : "Loading..."
  const memberCount = participants.length
  const members = participants.map((m: any) => ({
    ...m,
    profiles: Array.isArray(m.profiles) ? m.profiles[0] : m.profiles
  }))
  const existingMemberIds = members.map((m: any) => m.user_id)
  const filteredAddMemberUsers = allUsers.filter(
    (u) => !existingMemberIds.includes(u.id)
  )
  const typingText =
    typingUsers.length > 0 || isTyping ? "User is typing..." : ""
  const lastMessage = messages[messages.length - 1]
  const allSeen =
    !!lastMessage &&
    !lastMessage.is_system &&
    Array.isArray(lastMessage.seen_by) &&
    participants.every((p: any) =>
      p.user_id === lastMessage.sender_id || lastMessage.seen_by.includes(p.user_id)
    )

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] flex justify-center text-white px-4 pb-4 mt-0 pt-2 w-full overflow-hidden">

        <div className="w-full max-w-3xl h-[calc(100vh-80px)] bg-black/30 border border-white/10 rounded-xl flex flex-col overflow-hidden">

          {/* HEADER */}
          <div className="shrink-0 flex items-center justify-between px-3 py-2 border-b border-white/10 md:p-4 md:justify-start md:gap-3">

            <button
              onClick={() => router.push("/messages")}
              className="p-2 md:text-sm md:px-3 md:py-1 md:bg-white/10 md:rounded md:hover:bg-white/20"
            >
              ←
            </button>

            <div className="flex items-center gap-3">
              {conversation?.is_group ? (
                <img
                  src={
                    conversation.avatar_url || "/group-default.png"
                  }
                  onError={(e) => {
                    e.currentTarget.src = "/group-default.png"
                  }}
                  className="hidden h-10 w-10 rounded-full object-cover transition hover:scale-105 cursor-pointer md:block"
                />
              ) : null}
              <div className="flex flex-col leading-tight">
                <span className="text-sm font-semibold">
                  {conversation?.is_group
                    ? conversation?.name || "Group Chat"
                    : title}
                </span>
                <span className="text-xs text-gray-400">
                  {conversation?.is_group
                    ? `Group Chat • ${memberCount} members`
                    : `Direct Message • ${memberCount} members`}
                </span>
              </div>
            </div>

            <div className="ml-auto flex items-center gap-2">
              <button
                onClick={() => {
                  if (conversation?.is_group) {
                    setGroupName(conversation?.name || "")
                    setShowGroupSettings(true)
                    return
                  }
                  router.push("/settings")
                }}
                className="p-2 md:px-3 md:py-1 md:bg-white/10 md:rounded md:hover:bg-white/20 md:text-sm"
              >
                ⚙️
              </button>
            </div>

          </div>

          {/* MESSAGES */}
          <div
            ref={scrollRef}
            className="min-h-0 flex-1 overflow-y-auto overflow-x-visible px-2 py-3 md:p-4"
          >
            {messages.map((message, i) => {
              if (message.is_system) {
                return (
                  <div
                    key={message.id}
                    className="text-center text-gray-400 text-sm my-2"
                  >
                    {message.content}
                  </div>
                )
              }

              const prevMessage = messages[i - 1]
              const isMe = message.sender_id === user?.id
              const isGroup = Boolean(conversation?.is_group)
              const showName =
                isGroup &&
                !isMe &&
                (!prevMessage ||
                  prevMessage.sender_id !== message.sender_id)

              const isNewSender =
                !prevMessage || prevMessage.sender_id !== message.sender_id

              const rowClass = `flex flex-col ${isNewSender ? "mt-3" : "mt-1"}`

              const profileRow = Array.isArray(message.profiles)
                ? message.profiles[0]
                : message.profiles
              const profileUsername =
                profileRow?.username ?? message.profiles?.username

              if (message.type === "trade") {
                return (
                  <div key={message.id} className={rowClass}>
                    {showName && profileUsername ? (
                      <p className="text-xs text-gray-400 mb-1 ml-1">
                        {profileUsername}
                      </p>
                    ) : null}
                    <TradeMessageBubble
                      message={message}
                      isMe={isMe}
                      userId={user?.id}
                      activeMenuId={activeMenuId}
                      setActiveMenuId={setActiveMenuId}
                      deleteForMe={deleteForMe}
                      deleteForEveryone={deleteForEveryone}
                      onOpenTrade={openTradeModal}
                    />
                  </div>
                )
              }

              if (message.type === "post") {
                return (
                  <div key={message.id} className={rowClass}>
                    {showName && profileUsername ? (
                      <p className="text-xs text-gray-400 mb-1 ml-1">
                        {profileUsername}
                      </p>
                    ) : null}
                    <PostMessageBubble
                      message={message}
                      isMe={isMe}
                      userId={user?.id}
                      activeMenuId={activeMenuId}
                      setActiveMenuId={setActiveMenuId}
                      deleteForMe={deleteForMe}
                      deleteForEveryone={deleteForEveryone}
                      onOpenPost={openPostModal}
                    />
                  </div>
                )
              }

              const menuOpen = activeMenuId === message.id

              return (
                <div key={message.id} className={rowClass}>
                  {showName && profileUsername ? (
                    <p className="text-xs text-gray-400 mb-1 ml-1">
                      {profileUsername}
                    </p>
                  ) : null}
                  <div
                    className={`flex overflow-visible ${
                      isMe ? "justify-end" : "justify-start"
                    }`}
                  >
                    <div className="relative group inline-block max-w-[75%] overflow-visible">
                      <button
                        type="button"
                        onClick={() =>
                          setActiveMenuId(menuOpen ? null : message.id)
                        }
                        className={`absolute top-1 right-1 z-10 rounded px-1.5 py-0.5 text-xs text-gray-400 transition-opacity duration-200 hover:text-gray-200 ${
                          menuOpen
                            ? "opacity-100"
                            : "opacity-0 group-hover:opacity-100"
                        }`}
                        aria-label="Message actions"
                      >
                        ⋯
                      </button>

                      {menuOpen ? (
                        <div
                          className={`absolute top-7 z-50 w-40 rounded-lg border border-gray-600 bg-[#1e293b] shadow-lg ${
                            isMe ? "right-1" : "left-1"
                          }`}
                        >
                          <button
                            type="button"
                            onClick={() => deleteForMe(message)}
                            className="w-full text-left px-3 py-2 text-sm hover:bg-white/10"
                          >
                            Delete for me
                          </button>
                          {message.sender_id === user?.id ? (
                            <button
                              type="button"
                              onClick={() => deleteForEveryone(message)}
                              className="w-full text-left px-3 py-2 text-sm hover:bg-white/10"
                            >
                              Delete for everyone
                            </button>
                          ) : null}
                        </div>
                      ) : null}

                      <div
                        className={`p-3 rounded-xl overflow-visible ${
                          isMe ? "bg-blue-500" : "bg-gray-700"
                        }`}
                      >
                        {message.deleted_for_everyone ? (
                          <p className="text-gray-400 italic">
                            Message deleted
                          </p>
                        ) : (
                          <>
                            {message.content ? <p>{message.content}</p> : null}
                            {message.image_url ? (
                              <img
                                src={message.image_url}
                                className="mt-2 rounded-lg max-h-64"
                                alt=""
                              />
                            ) : null}
                          </>
                        )}
                      </div>
                    </div>
                  </div>
                </div>
              )
            })}
            {typingText ? (
              <p className="text-xs text-gray-400 italic">{typingText}</p>
            ) : null}
            <div id="chat-bottom" />
          </div>

          {/* INPUT */}
          {previewUrl ? (
            <div className="px-2 pb-2">
              <div className="relative w-fit">
                <img
                  src={previewUrl}
                  className="w-24 h-24 object-cover rounded-lg border border-white/10"
                  alt="Selected preview"
                />

                <button
                  onClick={removeImage}
                  className="absolute -top-2 -right-2 bg-red-500 text-white text-xs rounded-full w-5 h-5 flex items-center justify-center"
                >
                  ✕
                </button>
              </div>
            </div>
          ) : null}

          <div className="mt-auto shrink-0 border-t border-white/10 bg-[#0B1220] p-2 md:p-4 md:bg-[#020617]">
            <div className="flex items-center gap-1 w-full">
              <input
                type="text"
                placeholder="Send message..."
                value={input}
                onChange={(e) => {
                  setInput(e.target.value)
                  if (!isTyping) setIsTyping(true)
                }}
                className="flex-1 px-3 py-2 rounded bg-[#111827] text-white text-sm"
                onKeyDown={(e) => e.key === "Enter" && sendMessage()}
              />
              <label className="p-2 bg-[#1f2937] rounded cursor-pointer flex items-center justify-center md:hover:bg-[#334155]">
                📷
                <input
                  ref={fileRef}
                  type="file"
                  accept="image/*"
                  onChange={handleImageChange}
                  className="hidden"
                />
              </label>
              <button
                type="button"
                onClick={() => setShowTradePicker(true)}
                className="p-2 bg-[#1f2937] rounded flex items-center justify-center md:hover:bg-[#334155]"
              >
                📊
              </button>
              <button
                type="button"
                onClick={sendMessage}
                className="px-3 py-2 bg-blue-500 hover:bg-blue-600 rounded text-sm whitespace-nowrap"
              >
                Send
              </button>
            </div>
            
            {allSeen ? (
              <p className="mt-2 text-xs text-gray-400">Seen</p>
            ) : null}
            {groupSettingsSuccess ? (
              <p className="mt-1 text-xs text-emerald-400">{groupSettingsSuccess}</p>
            ) : null}
            {selectedFile ? (
              <div className="mt-2 text-xs text-gray-400">
                <span>{selectedFile.name}</span>
              </div>
            ) : null}

          </div>
            
        </div>

      </div>

      {showGroupSettings && conversation?.is_group ? (
        <div
          className="fixed inset-0 bg-black/50 backdrop-blur-sm flex items-center justify-center z-50 p-4"
          onClick={() => {
            setShowGroupSettings(false)
            setShowAddMembers(false)
            setSelectedUsers([])
          }}
        >
          <div
            className="bg-[#0f172a] border border-gray-600 rounded-2xl p-6 w-full max-w-md shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="text-white text-xl font-semibold mb-4">
              Group Settings
            </h2>
            <div className="flex items-center gap-3 mb-3">
              <img
                src={
                  groupImage
                    ? URL.createObjectURL(groupImage)
                    : conversation?.avatar_url || "/group-default.png"
                }
                onError={(e) => {
                  e.currentTarget.src = "/group-default.png"
                }}
                className="w-16 h-16 rounded-full object-cover border border-gray-600 hover:scale-105 transition cursor-pointer"
              />
              <input
                type="file"
                accept="image/*"
                onChange={handleFileChange}
                className="text-gray-300 mt-2"
              />
            </div>
            <input
              value={groupName}
              onChange={(e) => setGroupName(e.target.value)}
              placeholder="Group name"
              className="w-full p-3 rounded-lg bg-[#1e293b] text-white border border-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
            <div className="mt-6">
              <p className="text-gray-400 text-sm mb-3">
                Members ({members.length})
              </p>

              <div className="flex flex-wrap gap-3">
                {members.map((m: any, i: number) => (
                  <div
                    key={i}
                    onClick={() =>
                      m.profiles?.id &&
                      router.push(`/profile/${m.profiles.id}`)
                    }
                    className="flex items-center gap-2 bg-[#1e293b] px-3 py-2 rounded-lg cursor-pointer hover:bg-[#334155] transition"
                  >
                    <img
                      src={m.profiles?.avatar_url || "/default-avatar.png"}
                      className="w-6 h-6 rounded-full"
                    />
                    <span className="text-white text-sm">
                      {m.profiles?.username}
                    </span>
                  </div>
                ))}
              </div>

              <div className="mt-4">
                <button
                  type="button"
                  onClick={() => setShowAddMembers(true)}
                  className="w-full bg-[#1e293b] hover:bg-[#334155] text-white py-2 rounded-lg transition"
                >
                  + Add Members
                </button>
              </div>
            </div>

            <div className="border-t border-gray-700 my-6" />

            <div className="mt-8 flex justify-end gap-3">
              <button
                type="button"
                onClick={() => setShowGroupSettings(false)}
                className="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded-lg"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={saveGroupSettings}
                disabled={savingGroupSettings}
                className="bg-blue-500 hover:bg-blue-600 text-white px-4 py-2 rounded-lg disabled:opacity-50"
              >
                {savingGroupSettings ? "Saving..." : "Save"}
              </button>
            </div>
            <button
              type="button"
              onClick={handleLeaveGroup}
              className="bg-red-500 hover:bg-red-600 text-white px-4 py-2 rounded-lg w-full mt-6"
            >
              Leave Group
            </button>
          </div>
        </div>
      ) : null}

      {showAddMembers && conversation?.is_group ? (
        <div
          className="fixed inset-0 bg-black/50 backdrop-blur-sm flex items-center justify-center z-[60] p-4 text-white"
          onClick={() => {
            setShowAddMembers(false)
            setSelectedUsers([])
          }}
        >
          <div
            className="bg-[#0f172a] border border-gray-600 rounded-2xl p-6 w-full max-w-md shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="text-white text-xl font-semibold mb-2">
              Add Members
            </h2>
            <p className="text-gray-400 text-sm">
              Choose people to add to this group
            </p>

            <div className="max-h-64 overflow-y-auto mt-3 space-y-2">
              {filteredAddMemberUsers.map((u) => {
                const selected = selectedUsers.some((s) => s.id === u.id)
                return (
                  <button
                    key={u.id}
                    type="button"
                    onClick={() => toggleUser(u)}
                    className={`flex w-full items-center gap-3 p-3 rounded-lg cursor-pointer transition ${
                      selected
                        ? "bg-blue-500/20"
                        : "hover:bg-[#1e293b]"
                    }`}
                  >
                    <img
                      src={u.avatar_url || "/default-avatar.png"}
                      alt=""
                      className="h-8 w-8 shrink-0 rounded-full object-cover"
                    />
                    <span className="text-left text-sm text-white">
                      @{u.username}
                    </span>
                  </button>
                )
              })}
            </div>

            <button
              type="button"
              onClick={handleAddUsers}
              disabled={selectedUsers.length === 0}
              className="bg-blue-500 hover:bg-blue-600 text-white px-4 py-2 rounded-lg w-full mt-4 disabled:opacity-50"
            >
              Add Selected
            </button>
            <button
              type="button"
              onClick={() => {
                setShowAddMembers(false)
                setSelectedUsers([])
              }}
              className="w-full mt-2 rounded-lg bg-gray-700 px-4 py-2 text-white hover:bg-gray-600"
            >
              Cancel
            </button>
          </div>
        </div>
      ) : null}

      {tradeModalTrade ? (
        <div
          className="fixed inset-0 z-[70] flex items-center justify-center bg-black/60 p-4 text-white backdrop-blur-sm"
          onClick={() => setTradeModalTrade(null)}
        >
          <div
            className="w-full max-w-md rounded-2xl border border-gray-600 bg-[#0f172a] p-6 shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            {(() => {
              const t = tradeModalTrade
              const modalImg = tradeScreenshotSrc(t.image_url)
              const p = Number(t.pnl)
              const win = !Number.isNaN(p) && p >= 0
              const modalStageRaw = getTradeStageRaw(t)
              const modalStageKey = modalStageRaw.toLowerCase()
              const modalStageFooterText = modalStageRaw || "Trade"
              return (
                <>
                  <div className="bg-gradient-to-br from-[#0f172a] to-[#1e293b] border border-gray-700 rounded-xl p-4 shadow-lg">
                    <div className="mb-2 flex items-center justify-between">
                      <div>
                        <p className="text-lg font-semibold text-white">
                          {t.ticker}
                        </p>
                        <p className="text-xs text-gray-400">{t.direction}</p>
                      </div>
                      <div
                        className={`text-sm font-semibold ${
                          win ? "text-green-400" : "text-red-400"
                        }`}
                      >
                        {Number.isNaN(p)
                          ? `$${t.pnl}`
                          : `${win ? "+" : "-"}$${Math.abs(p)}`}
                      </div>
                    </div>
                    <div className="mb-3 flex justify-between text-xs text-gray-400">
                      <span>RR: {t.rr}</span>
                      <span>Points: {t.points ?? "—"}</span>
                    </div>
                    {modalImg ? (
                      <img
                        src={modalImg}
                        alt=""
                        className="mb-3 max-h-64 w-full rounded-lg border border-gray-700 object-contain"
                      />
                    ) : null}
                    <div className="flex items-center justify-between text-xs">
                      <span
                        className={`px-2 py-1 rounded-md text-xs font-medium ${
                          modalStageKey === "live"
                            ? "bg-green-500/20 text-green-400"
                            : modalStageKey === "funded"
                              ? "bg-blue-500/20 text-blue-400"
                              : modalStageKey === "eval"
                                ? "bg-yellow-500/20 text-yellow-400"
                                : "bg-gray-500/20 text-gray-400"
                        }`}
                      >
                        {modalStageFooterText}
                      </span>
                      <span className="text-gray-500">Shared Trade</span>
                    </div>
                  </div>
                  <button
                    type="button"
                    onClick={() => setTradeModalTrade(null)}
                    className="mt-4 w-full rounded-lg bg-gray-700 px-4 py-2 text-white hover:bg-gray-600"
                  >
                    Close
                  </button>
                </>
              )
            })()}
          </div>
        </div>
      ) : null}

      {postModalPost ? (
        <div
          className="fixed inset-0 z-[70] flex items-center justify-center bg-black/60 p-4 text-white backdrop-blur-sm"
          onClick={() => setPostModalPost(null)}
        >
          <div
            className="w-full max-w-md rounded-2xl border border-gray-600 bg-[#0f172a] p-6 shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            {(() => {
              const p = postModalPost
              const imageSrc = postScreenshotSrc(p.image_url)
              const pnl = Number(p.pnl)
              const isWin = !Number.isNaN(pnl) && pnl >= 0
              return (
                <>
                  <div className="bg-gradient-to-br from-[#0f172a] to-[#1e293b] border border-gray-700 rounded-xl p-4 shadow-lg">
                    {imageSrc ? (
                      <img
                        src={imageSrc}
                        alt=""
                        className="mb-3 max-h-64 w-full rounded-lg border border-gray-700 object-contain"
                      />
                    ) : null}
                    <div className="flex justify-between text-sm">
                      <span className={isWin ? "text-emerald-400" : "text-red-400"}>
                        {Number.isNaN(pnl) ? "—" : `${isWin ? "+" : ""}$${pnl}`}
                      </span>
                      <span className="text-gray-300">
                        RR {p.rr != null && p.rr !== "" ? p.rr : "—"}
                      </span>
                    </div>
                  </div>
                  <button
                    type="button"
                    onClick={() => setPostModalPost(null)}
                    className="mt-4 w-full rounded-lg bg-gray-700 px-4 py-2 text-white hover:bg-gray-600"
                  >
                    Close
                  </button>
                </>
              )
            })()}
          </div>
        </div>
      ) : null}

      {showTradePicker ? (
        <div
          className="fixed inset-0 z-[60] flex items-center justify-center bg-black/50 p-4 text-white backdrop-blur-sm"
          onClick={() => setShowTradePicker(false)}
        >
          <div
            className="w-full max-w-md rounded-2xl border border-gray-600 bg-[#0f172a] p-6 shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="mb-3 text-xl font-semibold text-white">
              Send a trade
            </h2>
            <div className="max-h-80 space-y-2 overflow-y-auto">
              {trades.length === 0 ? (
                <p className="text-sm text-gray-400">No trades yet.</p>
              ) : (
                trades.map((trade) => (
                  <div
                    key={trade.id}
                    role="button"
                    tabIndex={0}
                    onClick={() => handleSendTrade(trade)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter" || e.key === " ") {
                        e.preventDefault()
                        handleSendTrade(trade)
                      }
                    }}
                    className="cursor-pointer rounded-lg bg-[#1e293b] p-3 hover:bg-[#334155]"
                  >
                    <p className="font-medium text-white">
                      {trade.ticker} • {trade.direction}
                    </p>
                    <p className="text-sm text-gray-400">
                      ${trade.pnl} • RR {trade.rr}
                    </p>
                  </div>
                ))
              )}
            </div>
            <button
              type="button"
              onClick={() => setShowTradePicker(false)}
              className="mt-4 w-full rounded-lg bg-gray-700 px-4 py-2 text-white hover:bg-gray-600"
            >
              Close
            </button>
          </div>
        </div>
      ) : null}
    </>
  )
}