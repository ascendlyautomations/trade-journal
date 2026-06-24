"use client"

import Navbar from "../../components/Navbar"
import DmStyleComposer from "../../components/DmStyleComposer"
import SharedTradeMessageCard from "@/app/components/SharedTradeMessageCard"
import FeedPostScreenshot from "@/app/components/feed/FeedPostScreenshot"
import {
  Fragment,
  useCallback,
  useEffect,
  useMemo,
  useState,
  useRef,
  type ChangeEvent,
} from "react"
import {
  formatConversationDateDividerLabel,
  formatDmClusterTime,
  shouldShowDmClusterTimestamp,
  shouldShowDmDateDivider,
} from "@/lib/formatMessageTimestamp"
import { supabase } from "../../../lib/supabaseClient"
import { compressImage, compressScreenshot } from "@/lib/compressImage"
import { feedbackPresets } from "@/lib/feedbackPresets"
import { logSupabaseError } from "@/lib/logSupabaseError"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import EmptyState from "@/app/components/ui/EmptyState"
import { useParams, useRouter } from "next/navigation"
import {
  formatMoneyUnknown,
  formatRR,
  formatSignedPnlDisplay,
} from "@/lib/formatDisplay"
import { isConversationParticipant } from "@/lib/conversationAccess"
import { ensureDmConversation } from "@/lib/dmConversation"
import {
  dispatchConversationInboxPatch,
  previewFromMessage,
  updateConversationPreview,
} from "@/lib/conversationInboxSync"
import {
  buildDmThreadPath,
  isConversationUuidSegment,
} from "@/lib/messageRoutes"
import {
  getSharedPostViewHref,
  getSharedTradeViewHref,
  SHARED_POST_UNAVAILABLE,
  SHARED_TRADE_UNAVAILABLE,
} from "@/lib/sharedContentNavigation"
import {
  ProfileAvatarLink,
  ProfileLink,
  ProfileUsernameLink,
} from "@/app/components/ProfileLink"
import { profilePostPublicUrl } from "@/lib/storagePublicUrl"
import { normalizeProfileUsername } from "@/lib/profileUsername"
import { isTradeOwnedByUser } from "@/lib/tradeShareAccess"
import ReplyComposerStrip from "@/app/components/replies/ReplyComposerStrip"
import ReplyReferenceBlock from "@/app/components/replies/ReplyReferenceBlock"
import ImageLightbox from "@/app/components/ui/ImageLightbox"
import {
  buildReplyTargetFromMessage,
  dmMessageElementId,
  indexCommentsById,
  resolveParentMessage,
  scrollToReplyTarget,
  type ReplyParentMessageLike,
  type ReplyTarget,
} from "@/lib/replyReference"

/** Includes parent_message_id via *; no self-referencing parent embed (PGRST200). */
const DM_MESSAGE_SELECT = `
  *,
  profiles!sender_id (
    username,
    avatar_url
  )
`

const DM_SHARE_CARD_CLASS = "w-full max-w-[min(100%,22rem)]"

function legacyShareCardCaption(content: string | null | undefined): string | null {
  const trimmed = content?.trim() ?? ""
  if (!trimmed) return null
  if (trimmed === "Shared a trade" || trimmed === "Shared a post") return null
  return trimmed
}

type ConversationPageAccess =
  | "loading"
  | "allowed"
  | "unavailable"
  | "unauthenticated"

function ConversationDateDivider({ label }: { label: string }) {
  if (!label) return null
  return (
    <div
      className="my-4 flex items-center gap-3 px-1"
      role="separator"
      aria-label={label}
    >
      <div className="h-px min-w-0 flex-1 bg-white/10" aria-hidden />
      <span className="shrink-0 text-[11px] font-medium tracking-wide text-gray-500">
        {label}
      </span>
      <div className="h-px min-w-0 flex-1 bg-white/10" aria-hidden />
    </div>
  )
}

function DmClusterTimestamp({
  createdAt,
  isMe,
}: {
  createdAt: string | null | undefined
  isMe: boolean
}) {
  const label = formatDmClusterTime(createdAt)
  if (!label) return null
  return (
    <p
      className={`mt-1 px-1 text-[11px] leading-none text-gray-500 ${
        isMe ? "self-end text-right" : "self-start text-left"
      }`}
    >
      <time dateTime={createdAt ?? undefined}>{label}</time>
    </p>
  )
}

function postScreenshotSrc(url: string | null | undefined): string | null {
  const raw = url != null ? String(url).trim() : ""
  if (!raw) return null
  if (raw.startsWith("http")) return raw
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return null
  return `${base}/storage/v1/object/public/screenshots/${raw}`
}

function DmReplyReference({
  message,
  parentMessage,
  onJumpToParent,
  onUnavailable,
}: {
  message: any
  parentMessage?: ReplyParentMessageLike | null
  onJumpToParent: (parentId: string) => boolean
  onUnavailable: () => void
}) {
  if (!message.parent_message_id) return null
  const parentId = String(parentMessage?.id ?? message.parent_message_id)
  return (
    <ReplyReferenceBlock
      parentMessageId={message.parent_message_id}
      parentMessage={parentMessage}
      targetElementId={dmMessageElementId(parentId)}
      onJumpToParent={() => onJumpToParent(parentId)}
      onUnavailable={onUnavailable}
    />
  )
}

function DmMessageActionMenu({
  message,
  isMe,
  userId,
  menuOpen,
  setActiveMenuId,
  onReply,
  deleteForMe,
  deleteForEveryone,
  alignRight,
}: {
  message: any
  isMe: boolean
  userId: string | undefined
  menuOpen: boolean
  setActiveMenuId: (id: string | null) => void
  onReply: (message: any) => void
  deleteForMe: (m: any) => void
  deleteForEveryone: (m: any) => void
  alignRight: boolean
}) {
  return (
    <>
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
            alignRight ? "right-1" : "left-1"
          }`}
        >
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation()
              onReply(message)
            }}
            className="w-full px-3 py-2 text-left text-sm hover:bg-white/10"
          >
            Reply
          </button>
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
    </>
  )
}

function TradeMessageBubble({
  message,
  isMe,
  userId,
  activeMenuId,
  setActiveMenuId,
  deleteForMe,
  deleteForEveryone,
  onViewTrade,
  onReply,
  onJumpToParent,
  onReplyUnavailable,
  parentMessage,
}: {
  message: any
  isMe: boolean
  userId: string | undefined
  activeMenuId: string | null
  setActiveMenuId: (id: string | null) => void
  deleteForMe: (m: any) => void
  deleteForEveryone: (m: any) => void
  onViewTrade: (trade: any) => void
  onReply: (message: any) => void
  onJumpToParent: (parentId: string) => boolean
  onReplyUnavailable: () => void
  parentMessage?: ReplyParentMessageLike | null
}) {
  if (message.deleted_for_everyone) {
    return (
      <div className={`flex ${isMe ? "justify-end" : "justify-start"}`}>
        <p className="text-gray-400 italic text-sm">Message deleted</p>
      </div>
    )
  }

  const isMine = message.sender_id === userId
  const menuOpen = activeMenuId === message.id

  return (
    <div
      id={dmMessageElementId(message.id)}
      data-dm-message-id={message.id}
      className={`flex ${isMe ? "justify-end" : "justify-start"}`}
    >
      <div className={`relative group ${DM_SHARE_CARD_CLASS} overflow-visible`}>
        <DmMessageActionMenu
          message={message}
          isMe={isMe}
          userId={userId}
          menuOpen={menuOpen}
          setActiveMenuId={setActiveMenuId}
          onReply={onReply}
          deleteForMe={deleteForMe}
          deleteForEveryone={deleteForEveryone}
          alignRight={isMine}
        />

        <SharedTradeMessageCard
          tradeId={message.trade_id}
          viewerUserId={userId}
          onViewTrade={onViewTrade}
          layout="dm"
          beforeCardContent={
            <DmReplyReference
              message={message}
              parentMessage={parentMessage}
              onJumpToParent={onJumpToParent}
              onUnavailable={onReplyUnavailable}
            />
          }
        />
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
  onViewPost,
  onReply,
  onJumpToParent,
  onReplyUnavailable,
  parentMessage,
}: {
  message: any
  isMe: boolean
  userId: string | undefined
  activeMenuId: string | null
  setActiveMenuId: (id: string | null) => void
  deleteForMe: (m: any) => void
  deleteForEveryone: (m: any) => void
  onViewPost: (post: any) => void
  onReply: (message: any) => void
  onJumpToParent: (parentId: string) => boolean
  onReplyUnavailable: () => void
  parentMessage?: ReplyParentMessageLike | null
}) {
  const [post, setPost] = useState<any>(null)
  const [postLoading, setPostLoading] = useState(false)
  const [lightboxImageUrl, setLightboxImageUrl] = useState<string | null>(null)
  const isProfileShare =
    message.type === "profile_post" || Boolean(message.profile_post_id)

  useEffect(() => {
    const profilePostId =
      message.profile_post_id != null ? String(message.profile_post_id) : ""
    const tradePostId = message.post_id != null ? String(message.post_id) : ""

    if (isProfileShare) {
      if (!profilePostId) {
        setPost(null)
        setPostLoading(false)
        return
      }
      let cancelled = false
      setPostLoading(true)
      setPost(null)
      ;(async () => {
        const { data } = await supabase
          .from("profile_posts")
          .select("*, profiles(username, avatar_url)")
          .eq("id", profilePostId)
          .maybeSingle()
        if (!cancelled) {
          setPost(data ?? null)
          setPostLoading(false)
        }
      })()
      return () => {
        cancelled = true
      }
    }

    if (!tradePostId) {
      setPost(null)
      setPostLoading(false)
      return
    }
    let cancelled = false
    setPostLoading(true)
    setPost(null)
    ;(async () => {
      const { data } = await supabase
        .from("posts")
        .select("*, profiles(username, avatar_url)")
        .eq("id", tradePostId)
        .maybeSingle()
      if (!cancelled) {
        setPost(data ?? null)
        setPostLoading(false)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [isProfileShare, message.post_id, message.profile_post_id])

  if (message.deleted_for_everyone) {
    return (
      <div className={`flex ${isMe ? "justify-end" : "justify-start"}`}>
        <p className="text-gray-400 italic text-sm">Message deleted</p>
      </div>
    )
  }

  if (postLoading) {
    return (
      <div className={`flex ${isMe ? "justify-end" : "justify-start"}`}>
        <div className="max-w-xs rounded-lg bg-[#1e293b] p-3 text-sm text-gray-400">
          Loading post…
        </div>
      </div>
    )
  }

  if (!post) {
    return (
      <div className={`flex ${isMe ? "justify-end" : "justify-start"}`}>
        <div className="max-w-xs rounded-lg bg-[#1e293b] p-3 text-sm italic text-gray-400">
          {SHARED_POST_UNAVAILABLE}
        </div>
      </div>
    )
  }

  const menuOpen = activeMenuId === message.id
  const imageSrc = isProfileShare
    ? profilePostPublicUrl(post.image_url)
    : postScreenshotSrc(post.image_url)
  const pnl = Number(post.pnl)
  const isWin = !Number.isNaN(pnl) && pnl >= 0
  const showTradeStats = !isProfileShare && !Number.isNaN(pnl)
  const legacyCaption = legacyShareCardCaption(message.content)

  return (
    <div
      id={dmMessageElementId(message.id)}
      data-dm-message-id={message.id}
      className={`flex ${isMe ? "justify-end" : "justify-start"}`}
    >
      <div className={`relative group ${DM_SHARE_CARD_CLASS} overflow-visible`}>
        <DmMessageActionMenu
          message={message}
          isMe={isMe}
          userId={userId}
          menuOpen={menuOpen}
          setActiveMenuId={setActiveMenuId}
          onReply={onReply}
          deleteForMe={deleteForMe}
          deleteForEveryone={deleteForEveryone}
          alignRight={isMe}
        />

        <div className="w-full overflow-hidden rounded-xl border border-white/10 bg-white/5 shadow-lg shadow-black/20">
          <DmReplyReference
            message={message}
            parentMessage={parentMessage}
            onJumpToParent={onJumpToParent}
            onUnavailable={onReplyUnavailable}
          />
          {legacyCaption ? (
            <p className="border-b border-white/10 px-4 pb-3 pt-3 text-sm text-gray-300">
              {legacyCaption}
            </p>
          ) : null}

          <div className="p-4">
            <div className="mb-2 flex items-center justify-between gap-3">
              <ProfileUsernameLink
                userId={String(post.user_id ?? post.profiles?.id ?? "")}
                username={post.profiles?.username}
                stopPropagation
                className="text-sm font-semibold text-white hover:underline"
              >
                @{post.profiles?.username || "User"}
              </ProfileUsernameLink>
              <span className="shrink-0 text-xs text-gray-400">Shared Post</span>
            </div>

            {imageSrc ? (
              <FeedPostScreenshot
                imageSrc={imageSrc}
                variant="detail"
                wrapperClassName="mb-3 w-full overflow-hidden rounded-lg border border-gray-700 bg-black/30"
                onImageClick={setLightboxImageUrl}
              />
            ) : null}

            {post.content ? (
              <p className="mb-3 text-sm leading-relaxed text-gray-200">
                {post.content}
              </p>
            ) : null}

            {showTradeStats ? (
              <div className="mb-3 flex justify-between text-xs">
                <span className={isWin ? "text-emerald-400" : "text-red-400"}>
                  {formatSignedPnlDisplay(pnl)}
                </span>
                <span className="text-gray-400">
                  RR {formatRR(post.rr)}
                </span>
              </div>
            ) : null}

            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation()
                onViewPost(post)
              }}
              className="w-full rounded-lg border border-blue-500/30 bg-blue-500/10 px-3 py-2 text-xs font-medium text-blue-300 transition hover:bg-blue-500/20 hover:text-blue-200"
            >
              View post →
            </button>
          </div>
        </div>

        <ImageLightbox
          open={lightboxImageUrl != null}
          imageUrl={lightboxImageUrl}
          onClose={() => setLightboxImageUrl(null)}
        />
      </div>
    </div>
  )
}

type TypingMember = {
  user_id: string
  profiles?: { name?: string | null; username?: string | null } | null
}

function buildTypingIndicatorText(
  typingUserIds: string[],
  currentUserId: string | undefined,
  members: TypingMember[],
  isGroup: boolean
): string {
  const others = typingUserIds.filter((id) => id && id !== currentUserId)
  if (others.length === 0) return ""

  const labelFor = (userId: string): string | null => {
    const member = members.find((m) => m.user_id === userId)
    const prof = member?.profiles
    const raw = (prof?.name || prof?.username || "").trim()
    return raw || null
  }

  if (!isGroup || others.length === 1) {
    const label = labelFor(others[0])
    return label ? `${label} is typing...` : "Someone is typing..."
  }

  return "Multiple users are typing..."
}

export default function DMPage() {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const params = useParams()
  const router = useRouter()
  const urlSegment = params.id as string
  const [activeConversationId, setActiveConversationId] = useState<string | null>(
    null
  )

  const [messages, setMessages] = useState<any[]>([])
  const [messagesLoaded, setMessagesLoaded] = useState(false)
  const [input, setInput] = useState("")
  const [replyTarget, setReplyTarget] = useState<ReplyTarget | null>(null)
  const replyTargetRef = useRef<ReplyTarget | null>(null)
  const [user, setUser] = useState<any>(null)
  const [selectedFile, setSelectedFile] = useState<File | null>(null)
  const [selectedImage, setSelectedImage] = useState<File | null>(null)
  const [previewUrl, setPreviewUrl] = useState<string | null>(null)
  const [otherUser, setOtherUser] = useState<any>(null)
  const [conversation, setConversation] = useState<any>(null)
  const [participants, setParticipants] = useState<any[]>([])
  const [activeMenuId, setActiveMenuId] = useState<string | null>(null)
  const [isTyping, setIsTyping] = useState(false)
  const [sendingMessage, setSendingMessage] = useState(false)
  const sendingMessageRef = useRef(false)
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
  const [lightboxImageUrl, setLightboxImageUrl] = useState<string | null>(null)
  const [trades, setTrades] = useState<any[]>([])
  const [pageAccess, setPageAccess] =
    useState<ConversationPageAccess>("loading")

  const scrollRef = useRef<HTMLDivElement>(null)
  const fileRef = useRef<HTMLInputElement>(null)
  const userIdRef = useRef<string | null>(null)
  const messagesChannelRef = useRef<ReturnType<typeof supabase.channel> | null>(
    null
  )

  function normalizeSeenBy(raw: unknown): string[] {
    if (Array.isArray(raw)) return raw.map(String)
    if (typeof raw === "string") {
      try {
        const parsed = JSON.parse(raw)
        if (Array.isArray(parsed)) return parsed.map(String)
      } catch {
        return []
      }
    }
    return []
  }

  useEffect(() => {
    userIdRef.current = user?.id ?? null
  }, [user?.id])

  useEffect(() => {
    replyTargetRef.current = replyTarget
  }, [replyTarget])

  function startReplyToMessage(message: any) {
    setReplyTarget(
      buildReplyTargetFromMessage({
        id: message.id,
        sender_id: message.sender_id,
        content: message.content,
        type: message.type,
        image_url: message.image_url,
        deleted_for_everyone: message.deleted_for_everyone,
        profiles: message.profiles,
      })
    )
    setActiveMenuId(null)
  }

  function scrollToDmMessage(messageId: string): boolean {
    return scrollToReplyTarget(dmMessageElementId(messageId), scrollRef.current)
  }

  function notifyReplyUnavailable() {
    showPopup({
      type: "info",
      message: "Original message unavailable",
    })
  }

  function viewSharedTrade(trade: { id?: string | null }) {
    const href = getSharedTradeViewHref(String(trade?.id ?? ""))
    router.push(href)
  }

  function viewSharedPost(post: Parameters<typeof getSharedPostViewHref>[0]) {
    router.push(getSharedPostViewHref(post))
  }

  useEffect(() => {
    init()
  }, [urlSegment])

  async function markMessageNotificationsRead(currentUserId: string) {
    console.log("[messages/[id]] mark read start", {
      userId: currentUserId,
      conversationId: activeConversationId,
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
      console.error("[messages/[id]] mark read error:", {
        userId: currentUserId,
        conversationId: activeConversationId,
        error,
      })
      return
    }

    console.log("[messages/[id]] mark read success", {
      userId: currentUserId,
      conversationId: activeConversationId,
      updated: count ?? data?.length ?? 0,
    })

    window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
  }

  useEffect(() => {
    if (!activeConversationId || pageAccess !== "allowed") return

    const topic = `messages-${activeConversationId}`
    supabase.getChannels().forEach((c) => {
      if (c.topic === topic) {
        supabase.removeChannel(c)
      }
    })

    const channel = supabase.channel(topic, {
      config: { broadcast: { self: false } },
    })
    messagesChannelRef.current = channel

    channel.on("broadcast", { event: "typing" }, (payload) => {
      const typingUserId = payload?.payload?.userId as string | undefined
      const uid = userIdRef.current
      if (!typingUserId || !uid || typingUserId === uid) return

      setTypingUsers((prev) => {
        if (prev.includes(typingUserId)) return prev
        return [...prev, typingUserId]
      })

      window.setTimeout(() => {
        setTypingUsers((prev) => prev.filter((id) => id !== typingUserId))
      }, 2000)
    })

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
                .select(DM_MESSAGE_SELECT)
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
      messagesChannelRef.current = null
      setTypingUsers([])
      supabase.removeChannel(channel)
    }
  }, [activeConversationId, pageAccess])

  useEffect(() => {
    const participantIds = new Set(participants.map((p: any) => p.user_id))
    setTypingUsers((prev) => prev.filter((id) => participantIds.has(id)))
  }, [participants])

  const sendTypingBroadcast = useCallback(() => {
    const channel = messagesChannelRef.current
    const uid = userIdRef.current
    if (!channel || !uid) return

    void channel.send({
      type: "broadcast",
      event: "typing",
      payload: { userId: uid },
    })
  }, [])

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
    setPageAccess("loading")
    setMessages([])
    setMessagesLoaded(false)
    setConversation(null)
    setParticipants([])
    setOtherUser(null)
    setActiveConversationId(null)

    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (!user) {
      setUser(null)
      setPageAccess("unauthenticated")
      router.push("/login")
      return
    }

    setUser(user)

    let conversationId: string | null = null

    if (isConversationUuidSegment(urlSegment)) {
      conversationId = urlSegment
    } else {
      const normalized = normalizeProfileUsername(urlSegment)
      if (!normalized) {
        setPageAccess("unavailable")
        return
      }

      const { data: prof } = await supabase
        .from("profiles")
        .select("id, username")
        .eq("username", normalized)
        .maybeSingle()

      if (!prof || prof.id === user.id) {
        setPageAccess("unavailable")
        return
      }

      const result = await ensureDmConversation(supabase, user.id, prof.id)
      if (!result.ok) {
        setPageAccess("unavailable")
        return
      }
      conversationId = result.conversationId
    }

    const allowed = await isConversationParticipant(conversationId, user.id)
    if (!allowed) {
      setPageAccess("unavailable")
      return
    }

    setActiveConversationId(conversationId)
    setPageAccess("allowed")
    await markMessageNotificationsRead(user.id)
    const details = await fetchConversationDetails(user.id, conversationId)
    await loadMessages(user.id, conversationId)

    if (
      isConversationUuidSegment(urlSegment) &&
      details &&
      !details.isGroup
    ) {
      const normalized = normalizeProfileUsername(
        details.otherProfile?.username ?? ""
      )
      if (normalized) {
        const target = buildDmThreadPath(normalized)
        const currentPath = `/messages/${urlSegment}`
        if (target !== currentPath) {
          router.replace(target, { scroll: false })
        }
      }
    }
  }

  async function fetchConversationDetails(
    currentUserId: string,
    conversationId: string
  ) {
    if (!(await isConversationParticipant(conversationId, currentUserId))) {
      return null
    }

    const { data: convo } = await supabase
      .from("conversations")
      .select("id, is_group, name, avatar_url")
      .eq("id", conversationId)
      .maybeSingle()

    setConversation(convo || null)

    const { data } = await supabase
      .from("conversation_participants")
      .select(`
        user_id,
        profiles (id, username, avatar_url)
      `)
      .eq("conversation_id", conversationId)

    setParticipants(data || [])

    const other = data?.find((u: any) => u.user_id !== currentUserId)
    const rawProfile = other?.profiles
    const otherProfile = Array.isArray(rawProfile) ? rawProfile[0] : rawProfile

    setOtherUser(otherProfile || null)

    return {
      isGroup: convo?.is_group === true,
      otherProfile: otherProfile ?? null,
    }
  }

  function scrollToBottom() {
    setTimeout(() => {
      if (scrollRef.current) {
        scrollRef.current.scrollTop = scrollRef.current.scrollHeight
      }
    }, 50)
  }

  async function loadMessages(currentUserId: string, conversationId: string) {
    if (!(await isConversationParticipant(conversationId, currentUserId))) {
      setMessagesLoaded(true)
      return
    }

    const { data: fetched } = await supabase
      .from("messages")
      .select(DM_MESSAGE_SELECT)
      .eq("conversation_id", conversationId)
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
    setMessagesLoaded(true)
  }

  async function markMessagesSeen(currentUserId: string) {
    if (pageAccess !== "allowed" || !activeConversationId) return

    const { data } = await supabase
      .from("messages")
      .select("id, seen_by, sender_id")
      .eq("conversation_id", activeConversationId)

    let updatedCount = 0
    for (const msg of data || []) {
      if (!msg.sender_id) continue
      if (msg.sender_id === currentUserId) continue
      const seenBy = normalizeSeenBy(msg.seen_by)
      if (seenBy.includes(currentUserId)) continue
      const nextSeenBy = [...seenBy, currentUserId]
      console.log("[messages/[id]] seen_by update attempt", {
        messageId: msg.id,
        oldSeenBy: seenBy,
        newSeenBy: nextSeenBy,
      })
      await supabase
        .from("messages")
        .update({ seen_by: nextSeenBy })
        .eq("id", msg.id)
      updatedCount += 1
    }

    const { data: verifyRows, error: verifyErr } = await supabase
      .from("messages")
      .select("id, sender_id, seen_by")
      .eq("conversation_id", activeConversationId)

    if (verifyErr) {
      console.error("[messages/[id]] verify seen_by error:", verifyErr)
    } else {
      const remainingUnread = (verifyRows || []).filter((r) => {
        if (!r.sender_id || r.sender_id === currentUserId) return false
        const seen = normalizeSeenBy(r.seen_by)
        return !seen.includes(currentUserId)
      })
      console.log("[messages/[id]] markMessagesSeen verify", {
        userId: currentUserId,
        conversationId: activeConversationId,
        updatedCount,
        remainingUnreadCount: remainingUnread.length,
        remainingUnreadMessageIds: remainingUnread.map((r) => r.id),
      })
    }
  }

  useEffect(() => {
    if (!user?.id || !activeConversationId || pageAccess !== "allowed") return
    void markMessagesSeen(user.id)
  }, [activeConversationId, user?.id, pageAccess])

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
    if (pageAccess !== "allowed" || !user?.id) return

    const file = e.target.files?.[0]
    if (!file || !conversation?.id) return

    setGroupImage(file)
    let uploadFile: File = file
    if (file.type?.startsWith("image/")) {
      uploadFile = await compressImage(file)
    }

    const fileName = `${conversation.id}-${Date.now()}-${uploadFile.name}`
    const filePath = `${fileName}`

    const { error: uploadError } = await supabase.storage
      .from("group-avatars")
      .upload(filePath, uploadFile, {
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
    if (sendingMessageRef.current || sendingMessage) return
    if (!user || pageAccess !== "allowed" || !activeConversationId) return
    if (!input.trim() && !selectedFile) return

    sendingMessageRef.current = true
    setSendingMessage(true)

    try {
    let imageUrl = null

    if (selectedFile) {
      let uploadFile: File = selectedFile
      if (selectedFile.type?.startsWith("image/")) {
        uploadFile = await compressScreenshot(selectedFile)
      }
      const fileName = `${Date.now()}-${uploadFile.name}`

      await supabase.storage
        .from("screenshots")
        .upload(fileName, uploadFile)

      imageUrl = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/screenshots/${fileName}`
    }

    const sendPayload = {
      conversation_id: activeConversationId,
      sender_id: user.id,
      content: input || "",
      image_url: imageUrl,
      channel: null,
      ...(replyTargetRef.current?.id
        ? { parent_message_id: replyTargetRef.current.id }
        : {}),
    }
    const { error: sendErr } = await supabase.from("messages").insert(sendPayload)
    if (sendErr) {
      logSupabaseError("sendMessage insert", sendErr, {
        table: "messages",
        query: "insert",
        payload: sendPayload,
        userId: user.id,
      })
      showPopup({ type: "error", message: handleSupabaseError(sendErr) })
      return
    }

    const preview = previewFromMessage({
      content: input || null,
      image_url: imageUrl,
    })
    const lastMessageAt = await updateConversationPreview(
      supabase,
      activeConversationId,
      preview
    )

    dispatchConversationInboxPatch({
      conversationId: activeConversationId,
      last_message: preview,
      last_message_at: lastMessageAt,
    })

    setInput("")
    setReplyTarget(null)
    setSelectedFile(null)
    setSelectedImage(null)
    setPreviewUrl(null)
    if (fileRef.current) fileRef.current.value = ""
    setIsTyping(false)
    } finally {
      sendingMessageRef.current = false
      setSendingMessage(false)
    }
  }

  async function handleSendTrade(trade: any) {
    if (sendingMessageRef.current || sendingMessage) return
    if (!user || pageAccess !== "allowed" || !activeConversationId) return

    if (!isTradeOwnedByUser(trade, user.id)) {
      showPopup({
        type: "error",
        message: "You can only share trades you own.",
      })
      return
    }

    sendingMessageRef.current = true
    setSendingMessage(true)

    try {
    const tradeSendPayload = {
      conversation_id: activeConversationId,
      sender_id: user.id,
      type: "trade",
      trade_id: trade.id,
      content: null,
      channel: null,
      ...(replyTargetRef.current?.id
        ? { parent_message_id: replyTargetRef.current.id }
        : {}),
    }
    const { error: tradeSendErr } = await supabase
      .from("messages")
      .insert(tradeSendPayload)
    if (tradeSendErr) {
      logSupabaseError("handleSendTrade insert", tradeSendErr, {
        table: "messages",
        query: "insert",
        payload: tradeSendPayload,
        userId: user.id,
      })
      showPopup({ type: "error", message: handleSupabaseError(tradeSendErr) })
      return
    }

    const lastMsg = previewFromMessage({ type: "trade" })
    const lastMessageAt = await updateConversationPreview(
      supabase,
      activeConversationId,
      lastMsg,
      undefined
    )

    dispatchConversationInboxPatch({
      conversationId: activeConversationId,
      last_message: lastMsg,
      last_message_at: lastMessageAt,
    })

    setShowTradePicker(false)
    setReplyTarget(null)
    } finally {
      sendingMessageRef.current = false
      setSendingMessage(false)
    }
  }

  async function saveGroupSettings() {
    if (!user || pageAccess !== "allowed") return
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
    if (!user || pageAccess !== "allowed") return
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
    if (!user || pageAccess !== "allowed") return
    if (!conversation?.id || selectedUsers.length === 0) return

    const toAdd = [...selectedUsers]
    const inserts = toAdd.map((u) => ({
      conversation_id: conversation.id,
      user_id: u.id,
    }))

    const { error: addParticipantsErr } = await supabase
      .from("conversation_participants")
      .insert(inserts)
    if (addParticipantsErr) {
      logSupabaseError("handleAddUsers conversation_participants insert", addParticipantsErr, {
        table: "conversation_participants",
        query: "insert",
        payload: inserts,
        userId: user.id,
        conversationId: conversation.id,
      })
      return
    }

    const meRow = participants.find((p: any) => p.user_id === user.id)
    const rawProf = meRow?.profiles
    const prof = Array.isArray(rawProf) ? rawProf[0] : rawProf
    const actorName = prof?.username || "Someone"

    const systemAddPayload = {
      conversation_id: conversation.id,
      content: `${actorName} added ${toAdd.map((u) => u.username).join(", ")}`,
      sender_id: null,
      is_system: true,
      channel: null,
    }
    const { error: systemAddErr } = await supabase
      .from("messages")
      .insert(systemAddPayload)
    if (systemAddErr) {
      logSupabaseError("handleAddUsers system message insert", systemAddErr, {
        table: "messages",
        query: "insert",
        payload: systemAddPayload,
        userId: user.id,
        conversationId: conversation.id,
      })
    }

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
    if (!user || pageAccess !== "allowed") return
    if (!conversation?.id || !conversation?.is_group) return

    const meRow = participants.find((p: any) => p.user_id === user.id)
    const rawProf = meRow?.profiles
    const prof = Array.isArray(rawProf) ? rawProf[0] : rawProf
    const displayName = prof?.username || "Someone"

    const leaveSystemPayload = {
      conversation_id: conversation.id,
      content: `${displayName} left the group`,
      sender_id: null,
      is_system: true,
      channel: null,
    }
    const { error: leaveSystemErr } = await supabase
      .from("messages")
      .insert(leaveSystemPayload)
    if (leaveSystemErr) {
      logSupabaseError("handleLeaveGroup system message insert", leaveSystemErr, {
        table: "messages",
        query: "insert",
        payload: leaveSystemPayload,
        userId: user.id,
        conversationId: conversation.id,
      })
      return
    }

    await supabase
      .from("conversation_participants")
      .delete()
      .eq("conversation_id", conversation.id)
      .eq("user_id", user.id)

    setShowGroupSettings(false)
    router.push("/messages")
  }

  async function deleteForEveryone(message: any) {
    if (!user || pageAccess !== "allowed") return
    if (message.sender_id !== user.id) return
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
  const typingText = buildTypingIndicatorText(
    typingUsers,
    user?.id,
    members,
    Boolean(conversation?.is_group)
  )

  const messagesById = useMemo(() => indexCommentsById(messages), [messages])
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
      <FeedbackModal {...feedbackModalProps} />

      {pageAccess !== "allowed" ? (
        <div className="flex h-[calc(100dvh-4rem)] min-h-0 w-full flex-col items-center justify-center gap-4 bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 text-white">
          <button
            type="button"
            onClick={() => router.push("/messages")}
            className="rounded-lg bg-white/10 px-4 py-2 text-sm hover:bg-white/20"
          >
            ← Back to messages
          </button>
          {pageAccess === "loading" ? (
            <p className="text-gray-300">Loading conversation...</p>
          ) : (
            <>
              <p className="text-lg font-semibold">
                This conversation is unavailable.
              </p>
              <p className="max-w-md text-center text-sm text-gray-400">
                You may not have access to this chat, or it no longer exists.
              </p>
            </>
          )}
        </div>
      ) : (
      <>
      <div className="flex h-[calc(100dvh-4rem)] min-h-0 w-full flex-col overflow-hidden bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 pb-4 pt-2 text-white">

        <div className="mx-auto flex h-full min-h-0 w-full max-w-3xl flex-col overflow-hidden rounded-xl border border-white/10 bg-black/30">

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
                  alt=""
                  loading="lazy"
                  decoding="async"
                  onError={(e) => {
                    e.currentTarget.src = "/group-default.png"
                  }}
                  className="hidden h-10 w-10 rounded-full object-cover transition hover:scale-105 cursor-pointer md:block"
                />
              ) : null}
              <div className="flex flex-col leading-tight">
                {conversation?.is_group ? (
                  <span className="text-sm font-semibold">
                    {conversation?.name || "Group Chat"}
                  </span>
                ) : otherUser?.id ? (
                  <ProfileUsernameLink
                    userId={otherUser.id}
                    username={otherUser.username}
                    className="text-sm font-semibold"
                  >
                    {title}
                  </ProfileUsernameLink>
                ) : (
                  <span className="text-sm font-semibold">{title}</span>
                )}
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
            {messagesLoaded && messages.length === 0 ? (
              <EmptyState
                title="No Messages Yet"
                description="Start the conversation."
                className="py-10"
              />
            ) : null}
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

              const parentMessage = resolveParentMessage(message, messagesById)

              const prevMessage = messages[i - 1]
              const isMe = message.sender_id === user?.id
              const isGroup = Boolean(conversation?.is_group)
              const showName =
                isGroup &&
                !isMe &&
                (!prevMessage ||
                  prevMessage.is_system ||
                  prevMessage.sender_id !== message.sender_id)

              const isNewSender =
                !prevMessage ||
                prevMessage.is_system ||
                prevMessage.sender_id !== message.sender_id

              const rowClass = `flex flex-col ${isNewSender ? "mt-3" : "mt-1"}`
              const showDateDivider = shouldShowDmDateDivider(messages, i)
              const dateDividerLabel = showDateDivider
                ? formatConversationDateDividerLabel(message.created_at)
                : ""
              const showTimestamp = shouldShowDmClusterTimestamp(messages, i)

              const profileRow = Array.isArray(message.profiles)
                ? message.profiles[0]
                : message.profiles
              const profileUsername =
                profileRow?.username ?? message.profiles?.username

              if (message.type === "trade") {
                return (
                  <Fragment key={message.id}>
                    {showDateDivider ? (
                      <ConversationDateDivider label={dateDividerLabel} />
                    ) : null}
                    <div className={rowClass}>
                      {showName && profileUsername ? (
                        <ProfileUsernameLink
                          userId={message.sender_id}
                          username={profileUsername}
                          className="mb-1 ml-1 inline-block text-xs text-gray-400 hover:text-gray-300"
                        />
                      ) : null}
                      <TradeMessageBubble
                        message={message}
                        isMe={isMe}
                        userId={user?.id}
                        activeMenuId={activeMenuId}
                        setActiveMenuId={setActiveMenuId}
                        deleteForMe={deleteForMe}
                        deleteForEveryone={deleteForEveryone}
                        onViewTrade={viewSharedTrade}
                        onReply={startReplyToMessage}
                        onJumpToParent={scrollToDmMessage}
                        onReplyUnavailable={notifyReplyUnavailable}
                        parentMessage={parentMessage}
                      />
                      {showTimestamp ? (
                        <DmClusterTimestamp
                          createdAt={message.created_at}
                          isMe={isMe}
                        />
                      ) : null}
                    </div>
                  </Fragment>
                )
              }

              if (message.type === "post" || message.type === "profile_post") {
                return (
                  <Fragment key={message.id}>
                    {showDateDivider ? (
                      <ConversationDateDivider label={dateDividerLabel} />
                    ) : null}
                    <div className={rowClass}>
                      {showName && profileUsername ? (
                        <ProfileUsernameLink
                          userId={message.sender_id}
                          username={profileUsername}
                          className="mb-1 ml-1 inline-block text-xs text-gray-400 hover:text-gray-300"
                        />
                      ) : null}
                      <PostMessageBubble
                        message={message}
                        isMe={isMe}
                        userId={user?.id}
                        activeMenuId={activeMenuId}
                        setActiveMenuId={setActiveMenuId}
                        deleteForMe={deleteForMe}
                        deleteForEveryone={deleteForEveryone}
                        onViewPost={viewSharedPost}
                        onReply={startReplyToMessage}
                        onJumpToParent={scrollToDmMessage}
                        onReplyUnavailable={notifyReplyUnavailable}
                        parentMessage={parentMessage}
                      />
                      {showTimestamp ? (
                        <DmClusterTimestamp
                          createdAt={message.created_at}
                          isMe={isMe}
                        />
                      ) : null}
                    </div>
                  </Fragment>
                )
              }

              const menuOpen = activeMenuId === message.id

              return (
                <Fragment key={message.id}>
                  {showDateDivider ? (
                    <ConversationDateDivider label={dateDividerLabel} />
                  ) : null}
                  <div className={rowClass}>
                    {showName && profileUsername ? (
                      <ProfileUsernameLink
                        userId={message.sender_id}
                        username={profileUsername}
                        className="mb-1 ml-1 inline-block text-xs text-gray-400 hover:text-gray-300"
                      />
                    ) : null}
                    <div
                      id={dmMessageElementId(message.id)}
                      data-dm-message-id={message.id}
                      className={`flex overflow-visible ${
                        isMe ? "justify-end" : "justify-start"
                      }`}
                    >
                      <div className="relative group inline-block max-w-[75%] overflow-visible">
                        <DmMessageActionMenu
                          message={message}
                          isMe={isMe}
                          userId={user?.id}
                          menuOpen={menuOpen}
                          setActiveMenuId={setActiveMenuId}
                          onReply={startReplyToMessage}
                          deleteForMe={deleteForMe}
                          deleteForEveryone={deleteForEveryone}
                          alignRight={isMe}
                        />

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
                              <DmReplyReference
                                message={message}
                                parentMessage={parentMessage}
                                onJumpToParent={scrollToDmMessage}
                                onUnavailable={notifyReplyUnavailable}
                              />
                              {message.image_url ? (
                                <button
                                  type="button"
                                  onClick={(e) => {
                                    e.stopPropagation()
                                    setLightboxImageUrl(message.image_url)
                                  }}
                                  className="block max-w-full cursor-zoom-in"
                                  aria-label="View image full screen"
                                >
                                  <img
                                    src={message.image_url}
                                    className="max-h-64 rounded-lg"
                                    alt=""
                                    loading="lazy"
                                    decoding="async"
                                  />
                                </button>
                              ) : null}
                              {message.content ? (
                                <p className={message.image_url ? "mt-2" : undefined}>
                                  {message.content}
                                </p>
                              ) : null}
                            </>
                          )}
                        </div>
                      </div>
                    </div>
                    {showTimestamp ? (
                      <DmClusterTimestamp
                        createdAt={message.created_at}
                        isMe={isMe}
                      />
                    ) : null}
                  </div>
                </Fragment>
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
                  loading="lazy"
                  decoding="async"
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

          <DmStyleComposer
            value={input}
            onChange={(v) => {
              setInput(v)
              if (!isTyping) {
                setIsTyping(true)
                sendTypingBroadcast()
              }
            }}
            onSend={() => void sendMessage()}
            placeholder="Send message..."
            sendDisabled={sendingMessage}
            onImageChange={handleImageChange}
            imageDisabled={false}
            fileInputRef={fileRef}
            onTradeClick={() => setShowTradePicker(true)}
            beforeRow={
              replyTarget ? (
                <ReplyComposerStrip
                  authorName={replyTarget.authorName}
                  preview={replyTarget.preview}
                  onCancel={() => setReplyTarget(null)}
                />
              ) : null
            }
            afterRow={
              <>
                {allSeen ? (
                  <p className="text-xs text-gray-400">Seen</p>
                ) : null}
                {groupSettingsSuccess ? (
                  <p className="mt-1 text-xs text-emerald-400">{groupSettingsSuccess}</p>
                ) : null}
                {selectedFile ? (
                  <div className="mt-1 text-xs text-gray-400">
                    <span>{selectedFile.name}</span>
                  </div>
                ) : null}
              </>
            }
          />
            
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
                alt=""
                loading="lazy"
                decoding="async"
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
                  <ProfileLink
                    key={i}
                    userId={m.profiles?.id ?? m.user_id}
                    username={m.profiles?.username}
                    className="flex cursor-pointer items-center gap-2 rounded-lg bg-[#1e293b] px-3 py-2 transition hover:bg-[#334155]"
                  >
                    <img
                      src={m.profiles?.avatar_url || "/default-avatar.png"}
                      alt=""
                      loading="lazy"
                      decoding="async"
                      className="h-6 w-6 rounded-full"
                    />
                    <span className="text-sm text-white">
                      {m.profiles?.username}
                    </span>
                  </ProfileLink>
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
                      loading="lazy"
                      decoding="async"
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
                <p className="text-sm text-gray-400">
                  No trades available to share.
                </p>
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
                      {formatMoneyUnknown(trade.pnl, { empty: "—" })} • RR {formatRR(trade.rr)}
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
      <ImageLightbox
        open={lightboxImageUrl != null}
        imageUrl={lightboxImageUrl}
        onClose={() => setLightboxImageUrl(null)}
      />
      </>
      )}
    </>
  )
}