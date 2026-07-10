"use client"

import DmStyleComposer from "../../components/DmStyleComposer"
import SharedTradeMessageCard from "@/app/components/SharedTradeMessageCard"
import FeedPostScreenshot from "@/app/components/feed/FeedPostScreenshot"
import {
  Fragment,
  useCallback,
  useEffect,
  useLayoutEffect,
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
import { devLog } from "@/lib/devLog"
import { compressImage, compressScreenshot } from "@/lib/compressImage"
import { feedbackPresets } from "@/lib/feedbackPresets"
import { LOADING_COPY } from "@/lib/loadingCopy"
import { logSupabaseError } from "@/lib/logSupabaseError"
import { dmSendFeedback } from "@/lib/dmSendFeedback"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import ImageCropModal from "@/app/components/ImageCropModal"
import { useImageCropUpload } from "@/lib/useImageCropUpload"
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
import { FEED_ACHIEVEMENT_POSTS_SELECT } from "@/lib/achievementPostEngagement"
import { FEED_REELS_SELECT } from "@/lib/reelEngagement"
import {
  getSharedContentViewHref,
  getSharedPostViewHref,
  getSharedTradeViewHref,
  SHARED_POST_UNAVAILABLE,
  SHARED_TRADE_UNAVAILABLE,
} from "@/lib/sharedContentNavigation"
import {
  ProfileLink,
  ProfileUsernameLink,
} from "@/app/components/ProfileLink"
import { DmSenderNameLine } from "@/app/components/messages/DmSenderNameLine"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import {
  DELETED_USER_LABEL,
  isDirectConversationPeerDeleted,
} from "@/lib/deletedUserDisplay"
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
import {
  decodeStoryReplyContent,
  STORY_REPLY_MESSAGE_TYPE,
} from "@/lib/storyReplyMessage"
import { consumeConversationOpenFromInbox, consumeInboxConversationId, peekInboxConversationId } from "@/lib/conversationOpenIntent"
import {
  dmPostPreviewCacheKey,
  dmTradePreviewCacheKey,
} from "@/lib/conversationPreviewCache"
import { markConversationMessagesSeen } from "@/lib/conversationReadMarking"
import {
  computeNewestMessage,
  areConversationPreviewsReady,
  filterMessagesForUser,
  isScrollNearBottom,
  mergeMessageLists,
  sortMessagesByCreatedAt,
} from "@/lib/conversationMessageUtils"
import {
  isLastMessageInDom,
  scrollContainerToBottom,
} from "@/lib/conversationScroll"
import {
  findConversationSessionByUrlSegment,
  patchConversationSession,
  readConversationSession,
  type ConversationSessionSnapshot,
  setActiveConversationSession,
  updateConversationMessages,
  writeConversationSession,
} from "@/lib/conversationSessionCache"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import { isDemoUserId } from "@/lib/demo/constants"
import { isDemoSupabaseBlocked } from "@/lib/demo/demoSupabaseGuard"
import { getCachedTrades } from "@/lib/appDataCache"
import {
  fetchDemoConversationDetails,
  fetchDemoConversationMessages,
  resolveDemoConversationIdFromSegment,
} from "@/lib/demo/demoMessages"
import { queryDmMessages } from "@/lib/dmMessageSelect"

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
  initialTrade,
  onTradeLoaded,
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
  initialTrade?: any | null
  onTradeLoaded?: (trade: any | null) => void
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
          initialTrade={initialTrade}
          onTradeLoaded={onTradeLoaded}
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
  initialPost,
  onPostLoaded,
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
  initialPost?: any | null
  onPostLoaded?: (post: any | null) => void
}) {
  const [post, setPost] = useState<any>(initialPost ?? null)
  const [postLoading, setPostLoading] = useState(
    () => !initialPost && Boolean(dmPostPreviewCacheKey(message))
  )
  const [lightboxImageUrl, setLightboxImageUrl] = useState<string | null>(null)
  const isProfileShare =
    message.type === "profile_post" || Boolean(message.profile_post_id)
  const isAchievementShare =
    message.type === "achievement_post" || Boolean(message.achievement_post_id)
  const isReelShare =
    message.type === "reel" || Boolean(message.reel_id)

  useEffect(() => {
    const reelId =
      message.reel_id != null ? String(message.reel_id) : ""
    const achievementPostId =
      message.achievement_post_id != null
        ? String(message.achievement_post_id)
        : ""
    const profilePostId =
      message.profile_post_id != null ? String(message.profile_post_id) : ""
    const tradePostId = message.post_id != null ? String(message.post_id) : ""

    if (isReelShare) {
      if (!reelId) {
        setPost(null)
        setPostLoading(false)
        return
      }
      let cancelled = false
      if (!initialPost) {
        setPostLoading(true)
        setPost(null)
      }
      ;(async () => {
        const { data } = await supabase
          .from("reels")
          .select(FEED_REELS_SELECT)
          .eq("id", reelId)
          .maybeSingle()
        if (!cancelled) {
          const loaded = data
            ? { ...data, feedKind: "reel" as const }
            : null
          setPost(loaded)
          setPostLoading(false)
          onPostLoaded?.(loaded)
        }
      })()
      return () => {
        cancelled = true
      }
    }

    if (isAchievementShare) {
      if (!achievementPostId) {
        setPost(null)
        setPostLoading(false)
        return
      }
      let cancelled = false
      if (!initialPost) {
        setPostLoading(true)
        setPost(null)
      }
      ;(async () => {
        const { data } = await supabase
          .from("achievement_posts")
          .select(FEED_ACHIEVEMENT_POSTS_SELECT)
          .eq("id", achievementPostId)
          .maybeSingle()
        if (!cancelled) {
          setPost(data ?? null)
          setPostLoading(false)
          onPostLoaded?.(data ?? null)
        }
      })()
      return () => {
        cancelled = true
      }
    }

    if (isProfileShare) {
      if (!profilePostId) {
        setPost(null)
        setPostLoading(false)
        return
      }
      let cancelled = false
      if (!initialPost) {
        setPostLoading(true)
        setPost(null)
      }
      ;(async () => {
        const { data } = await supabase
          .from("profile_posts")
          .select("*, profiles(username, avatar_url)")
          .eq("id", profilePostId)
          .maybeSingle()
        if (!cancelled) {
          setPost(data ?? null)
          setPostLoading(false)
          onPostLoaded?.(data ?? null)
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
    if (!initialPost) {
      setPostLoading(true)
      setPost(null)
    }
    ;(async () => {
      const { data } = await supabase
        .from("posts")
        .select("*, profiles(username, avatar_url)")
        .eq("id", tradePostId)
        .maybeSingle()
      if (!cancelled) {
        setPost(data ?? null)
        setPostLoading(false)
        onPostLoaded?.(data ?? null)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [
    isAchievementShare,
    isProfileShare,
    isReelShare,
    message.achievement_post_id,
    message.post_id,
    message.profile_post_id,
    message.reel_id,
    initialPost,
    onPostLoaded,
  ])

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
  const imageSrc = isReelShare
    ? post.thumbnail_url != null
      ? String(post.thumbnail_url)
      : null
    : isProfileShare
      ? profilePostPublicUrl(post.image_url)
      : postScreenshotSrc(post.image_url)
  const pnl = Number(post.pnl)
  const isWin = !Number.isNaN(pnl) && pnl >= 0
  const showTradeStats =
    !isProfileShare && !isAchievementShare && !isReelShare && !Number.isNaN(pnl)
  const legacyCaption = legacyShareCardCaption(message.content)
  const achievementTitle = isAchievementShare
    ? String(
        (post as { achievements?: { title?: string } })?.achievements?.title ??
          "Achievement"
      )
    : null
  const reelCaption =
    isReelShare && post.caption != null ? String(post.caption).trim() : ""
  const shareLabel = isReelShare
    ? "Shared Clip"
    : isAchievementShare
      ? "Shared Achievement"
      : isProfileShare
        ? "Shared Post"
        : "Shared Post"

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
            <p className="whitespace-pre-wrap break-words border-b border-white/10 px-4 pb-3 pt-3 text-sm text-gray-300">
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
              <span className="shrink-0 text-xs text-gray-400">{shareLabel}</span>
            </div>

            {isAchievementShare ? (
              <p className="mb-3 text-sm font-medium text-amber-200">
                🏆 {achievementTitle}
              </p>
            ) : null}

            {imageSrc ? (
              <FeedPostScreenshot
                imageSrc={imageSrc}
                variant="detail"
                wrapperClassName="mb-3 w-full overflow-hidden rounded-lg border border-gray-700 bg-black/30"
                onImageClick={setLightboxImageUrl}
              />
            ) : null}

            {post.content ? (
              <p className="mb-3 whitespace-pre-wrap break-words text-sm leading-relaxed text-gray-200">
                {post.content}
              </p>
            ) : null}

            {reelCaption ? (
              <p className="mb-3 whitespace-pre-wrap break-words text-sm leading-relaxed text-gray-200">
                {reelCaption}
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
              View{" "}
              {isReelShare
                ? "clip"
                : isAchievementShare
                  ? "achievement"
                  : "post"}{" "}
              →
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

function StoryReplyMessageBubble({
  message,
  isMe,
  userId,
  activeMenuId,
  setActiveMenuId,
  deleteForMe,
  deleteForEveryone,
  onReply,
  onJumpToParent,
  onReplyUnavailable,
  parentMessage,
  onMediaLoad,
}: {
  message: any
  isMe: boolean
  userId: string | undefined
  activeMenuId: string | null
  setActiveMenuId: (id: string | null) => void
  deleteForMe: (m: any) => void
  deleteForEveryone: (m: any) => void
  onReply: (message: any) => void
  onJumpToParent: (parentId: string) => boolean
  onReplyUnavailable: () => void
  parentMessage?: ReplyParentMessageLike | null
  onMediaLoad?: () => void
}) {
  if (message.deleted_for_everyone) {
    return (
      <div className={`flex ${isMe ? "justify-end" : "justify-start"}`}>
        <p className="text-sm italic text-gray-400">Message deleted</p>
      </div>
    )
  }

  const payload = decodeStoryReplyContent(message.content)
  const replyText = payload?.text?.trim() ?? ""
  const storyImageUrl = payload?.story_image_url?.trim() ?? ""
  const contextLabel = isMe ? "Replied to their story" : "Replied to your story"
  const menuOpen = activeMenuId === message.id

  return (
    <div
      id={dmMessageElementId(message.id)}
      data-dm-message-id={message.id}
      className={`flex ${isMe ? "justify-end" : "justify-start"}`}
    >
      <div className="relative group inline-block max-w-[min(100%,18rem)] overflow-visible">
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

        <div
          className={`overflow-hidden rounded-2xl border border-white/10 bg-[#1e293b] shadow-lg shadow-black/20 ${
            isMe ? "rounded-br-md" : "rounded-bl-md"
          }`}
        >
          <DmReplyReference
            message={message}
            parentMessage={parentMessage}
            onJumpToParent={onJumpToParent}
            onUnavailable={onReplyUnavailable}
          />

          <div className="flex items-center gap-2 border-b border-white/10 px-3 py-2">
            {storyImageUrl ? (
              <img
                src={storyImageUrl}
                alt=""
                className="h-10 w-10 shrink-0 rounded-md object-cover ring-1 ring-white/15"
                draggable={false}
                onLoad={onMediaLoad}
                onError={onMediaLoad}
              />
            ) : (
              <div className="h-10 w-10 shrink-0 rounded-md bg-white/10" />
            )}
            <p className="min-w-0 text-xs font-medium text-gray-400">
              {contextLabel}
            </p>
          </div>

          {replyText ? (
            <p className="whitespace-pre-wrap break-words px-3 py-2.5 text-sm text-gray-100">
              {replyText}
            </p>
          ) : null}
        </div>
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
  const { user: profileUser } = useUserProfile()
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
  const [tradesById, setTradesById] = useState<Record<string, any>>({})
  const [postsById, setPostsById] = useState<Record<string, any>>({})
  const [messageLayoutGeneration, setMessageLayoutGeneration] = useState(0)
  const [pageAccess, setPageAccess] =
    useState<ConversationPageAccess>("loading")

  const uploadGroupAvatar = useCallback(
    async (file: File) => {
      if (pageAccess !== "allowed" || !user?.id || !conversation?.id) return

      setGroupImage(file)
      let uploadFile: File = file
      if (file.type?.startsWith("image/")) {
        uploadFile = await compressImage(file)
      }

      const fileName = `${conversation.id}-${Date.now()}-${uploadFile.name}`
      const { error: uploadError } = await supabase.storage
        .from("group-avatars")
        .upload(fileName, uploadFile, {
          cacheControl: "3600",
          upsert: true,
        })

      if (uploadError) {
        console.error("Upload error:", uploadError)
        return
      }

      const { data: publicUrlData } = supabase.storage
        .from("group-avatars")
        .getPublicUrl(fileName)

      const publicUrl = publicUrlData.publicUrl

      await supabase
        .from("conversations")
        .update({ avatar_url: publicUrl })
        .eq("id", conversation.id)

      setConversation((prev: any) =>
        prev?.avatar_url === publicUrl ? prev : { ...prev, avatar_url: publicUrl }
      )
    },
    [conversation, pageAccess, user?.id]
  )

  const dmImageCrop = useImageCropUpload({
    preset: "content",
    onCropped: (file) => {
      setSelectedImage(file)
      setSelectedFile(file)
      setPreviewUrl(URL.createObjectURL(file))
    },
    onValidationError: (message) => showPopup({ type: "error", message }),
  })
  const groupImageCrop = useImageCropUpload({
    preset: "avatar",
    onCropped: (file) => {
      void uploadGroupAvatar(file)
    },
    onValidationError: (message) => showPopup({ type: "error", message }),
  })
  const fileRef = dmImageCrop.fileInputRef

  const scrollRef = useRef<HTMLDivElement>(null)
  const userIdRef = useRef<string | null>(null)
  const conversationIdRef = useRef<string | null>(null)
  const messagesChannelRef = useRef<ReturnType<typeof supabase.channel> | null>(
    null
  )
  const userNearBottomRef = useRef(true)
  const pendingSmoothScrollRef = useRef(false)
  const prevLastMessageIdRef = useRef<string | null>(null)
  const scrollAnchorRef = useRef<{
    conversationId: string
    lastMessageId: string | null
  } | null>(null)
  const persistConversationCacheRef = useRef<() => void>(() => {})
  const scrollPersistTimerRef = useRef<ReturnType<typeof setTimeout> | null>(
    null
  )
  const urlSegmentRef = useRef(urlSegment)
  urlSegmentRef.current = urlSegment
  const conversationMetaRef = useRef<{
    conversation: any | null
    participants: any[]
    otherUser: any | null
  }>({ conversation: null, participants: [], otherUser: null })
  const tradesByIdRef = useRef(tradesById)
  tradesByIdRef.current = tradesById
  const postsByIdRef = useRef(postsById)
  postsByIdRef.current = postsById
  const restoredFromCacheRef = useRef(false)

  const bumpMessageLayout = useCallback(() => {
    setMessageLayoutGeneration((generation) => generation + 1)
  }, [])

  const patchPreviewCache = useCallback(
    (patch: { tradesById?: Record<string, any>; postsById?: Record<string, any> }) => {
      const uid = userIdRef.current
      const cid = conversationIdRef.current
      if (!uid || !cid) return
      patchConversationSession(uid, cid, patch)
    },
    []
  )

  const handleTradePreviewLoaded = useCallback(
    (tradeId: string, trade: any | null) => {
      if (!trade) return
      const key = dmTradePreviewCacheKey(tradeId)
      if (!key) return
      setTradesById((prev) => {
        const next = { ...prev, [key]: trade }
        patchPreviewCache({ tradesById: next })
        return next
      })
    },
    [patchPreviewCache]
  )

  const handlePostPreviewLoaded = useCallback(
    (cacheKey: string, post: any | null) => {
      if (!post || !cacheKey) return
      setPostsById((prev) => {
        const next = { ...prev, [cacheKey]: post }
        patchPreviewCache({ postsById: next })
        return next
      })
    },
    [patchPreviewCache]
  )

  function applyCachedConversation(
    cached: ConversationSessionSnapshot,
    conversationId: string,
    sessionUser: { id: string }
  ) {
    setUser(sessionUser)
    setActiveConversationId(conversationId)
    setPageAccess("allowed")
    setMessages(cached.messages)
    setMessagesLoaded(true)
    setConversation(cached.conversation)
    setParticipants(cached.participants)
    setOtherUser(cached.otherUser)
    setInput(cached.draft)
    setReplyTarget(cached.replyTarget)
    setTradesById(cached.tradesById ?? {})
    setPostsById(cached.postsById ?? {})
    conversationMetaRef.current = {
      conversation: cached.conversation,
      participants: cached.participants,
      otherUser: cached.otherUser,
    }

    userNearBottomRef.current = true
    prevLastMessageIdRef.current = null
    scrollAnchorRef.current = {
      conversationId,
      lastMessageId: computeNewestMessage(cached.messages).id,
    }
  }

  useEffect(() => {
    userIdRef.current = user?.id ?? null
  }, [user?.id])

  useEffect(() => {
    conversationIdRef.current = activeConversationId
  }, [activeConversationId])

  useEffect(() => {
    setActiveConversationSession(user?.id ?? null, activeConversationId)
    return () => setActiveConversationSession(null, null)
  }, [user?.id, activeConversationId])

  useEffect(() => {
    replyTargetRef.current = replyTarget
  }, [replyTarget])

  const persistConversationCache = useCallback(() => {
    const uid = userIdRef.current
    const cid = conversationIdRef.current
    if (!uid || !cid || !messagesLoaded) return

    const el = scrollRef.current
    const scrollTop = el?.scrollTop ?? 0
    const scrollHeight = el?.scrollHeight ?? 0
    const clientHeight = el?.clientHeight ?? 0
    const wasAtBottom = el
      ? isScrollNearBottom(scrollTop, scrollHeight, clientHeight)
      : true
    const newest = computeNewestMessage(messages)

    writeConversationSession(uid, cid, {
      urlSegment: urlSegmentRef.current,
      messages,
      messagesLoaded,
      conversation,
      participants,
      otherUser,
      newestMessageId: newest.id,
      newestTimestamp: newest.timestamp,
      unreadCount: 0,
      scrollTop,
      wasAtBottom,
      draft: input,
      replyTarget,
      tradesById: tradesByIdRef.current,
      postsById: postsByIdRef.current,
    })
  }, [
    messages,
    messagesLoaded,
    conversation,
    participants,
    otherUser,
    input,
    replyTarget,
  ])

  persistConversationCacheRef.current = persistConversationCache

  const setMessagesWithCache = useCallback(
    (updater: (prev: any[]) => any[]) => {
      setMessages((prev) => {
        const next = updater(prev)
        const uid = userIdRef.current
        const cid = conversationIdRef.current
        if (uid && cid) {
          const meta = conversationMetaRef.current
          updateConversationMessages(uid, cid, () => next, {
            urlSegment: urlSegmentRef.current,
            conversation: meta.conversation,
            participants: meta.participants,
            otherUser: meta.otherUser,
            unreadCount: 0,
          })
        }
        return next
      })
    },
    []
  )

  const handleMessagesScroll = useCallback(() => {
    const el = scrollRef.current
    if (!el) return

    userNearBottomRef.current = isScrollNearBottom(
      el.scrollTop,
      el.scrollHeight,
      el.clientHeight
    )
    if (!userNearBottomRef.current) {
      scrollAnchorRef.current = null
    }

    const uid = userIdRef.current
    const cid = conversationIdRef.current
    if (!uid || !cid) return

    if (scrollPersistTimerRef.current) {
      clearTimeout(scrollPersistTimerRef.current)
    }
    scrollPersistTimerRef.current = setTimeout(() => {
      patchConversationSession(uid, cid, {
        scrollTop: el.scrollTop,
        wasAtBottom: userNearBottomRef.current,
      })
    }, 150)
  }, [])

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

  function viewSharedPost(post: Parameters<typeof getSharedContentViewHref>[0]) {
    router.push(getSharedContentViewHref(post))
  }

  async function markMessageNotificationsRead(currentUserId: string) {
    if (isDemoSupabaseBlocked()) return

    devLog("[messages/[id]] mark read start", {
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

    devLog("[messages/[id]] mark read success", {
      userId: currentUserId,
      conversationId: activeConversationId,
      updated: count ?? data?.length ?? 0,
    })

    window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
  }

  useEffect(() => {
    if (!activeConversationId || pageAccess !== "allowed") return
    if (isDemoSupabaseBlocked()) return

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
        devLog("Realtime event:", payload)

        if (payload.eventType === "INSERT") {
          const raw = payload.new as { id?: string; sender_id?: string }
          void (async () => {
            let row: any = raw
            if (raw.id) {
              const { data } = await queryDmMessages((select) =>
                supabase
                  .from("messages")
                  .select(select)
                  .eq("id", raw.id)
                  .maybeSingle()
              )
              if (data) row = data
            }
            setMessagesWithCache((prev) => {
              const without = prev.filter((x) => x.id !== raw.id)
              const updated = [...without, row]
              return sortMessagesByCreatedAt(updated)
            })

            const uid = userIdRef.current
            const senderId = raw.sender_id
            const cid = conversationIdRef.current
            if (uid && senderId && senderId !== uid && cid) {
              void markConversationMessagesSeen(uid, cid)
            }
          })()
        }

        if (payload.eventType === "UPDATE") {
          setMessagesWithCache((prev) =>
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
  }, [activeConversationId, pageAccess, setMessagesWithCache])

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

  useLayoutEffect(() => {
    if (!messagesLoaded || !activeConversationId) return
    const el = scrollRef.current
    if (!el) return

    const lastMsg = messages[messages.length - 1]
    const lastId = lastMsg ? String(lastMsg.id) : null

    if (pendingSmoothScrollRef.current) {
      pendingSmoothScrollRef.current = false
      scrollContainerToBottom(el, { behavior: "smooth" })
      prevLastMessageIdRef.current = lastId
      userNearBottomRef.current = true
      return
    }

    if (scrollAnchorRef.current && userNearBottomRef.current) {
      scrollContainerToBottom(el, { behavior: "auto" })

      const atBottom = isScrollNearBottom(
        el.scrollTop,
        el.scrollHeight,
        el.clientHeight
      )
      const previewsReady = areConversationPreviewsReady(
        messages,
        tradesById,
        postsById,
        dmTradePreviewCacheKey,
        dmPostPreviewCacheKey
      )
      const lastInDom = isLastMessageInDom(lastId, el, lastMsg)

      if (atBottom && previewsReady && lastInDom) {
        scrollAnchorRef.current = null
      }
    } else if (
      lastId &&
      lastId !== prevLastMessageIdRef.current &&
      userNearBottomRef.current
    ) {
      scrollContainerToBottom(el, { behavior: "smooth" })
    }

    prevLastMessageIdRef.current = lastId
  }, [
    messages,
    messagesLoaded,
    activeConversationId,
    tradesById,
    postsById,
    messageLayoutGeneration,
  ])

  useEffect(() => {
    if (!isTyping) return
    const timer = setTimeout(() => setIsTyping(false), 1200)
    return () => clearTimeout(timer)
  }, [isTyping, input])

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

    if (isDemoUserId(user.id)) {
      setTrades(getCachedTrades(user.id) ?? [])
      return
    }

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

  async function fetchConversationDeletedMessageIds(
    currentUserId: string,
    messageIds: string[]
  ): Promise<Set<string>> {
    if (messageIds.length === 0) return new Set()
    if (isDemoSupabaseBlocked()) return new Set()
    const { data } = await supabase
      .from("message_deletions")
      .select("message_id")
      .eq("user_id", currentUserId)
      .in("message_id", messageIds)
    return new Set((data || []).map((row) => String(row.message_id)))
  }

  async function syncNewerMessages(
    currentUserId: string,
    conversationId: string,
    cached: ConversationSessionSnapshot
  ) {
    if (isDemoSupabaseBlocked()) return
    if (!(await isConversationParticipant(conversationId, currentUserId))) return

    if (!cached.newestTimestamp) return

    const { data: incoming } = await queryDmMessages((select) =>
      supabase
        .from("messages")
        .select(select)
        .eq("conversation_id", conversationId)
        .gt("created_at", cached.newestTimestamp)
        .order("created_at", { ascending: true })
    )

    if (!incoming?.length) return

    const deletedIds = await fetchConversationDeletedMessageIds(
      currentUserId,
      cached.messages.map((message) => String(message.id))
    )

    setMessagesWithCache((prev) => {
      const merged = mergeMessageLists(prev, incoming)
      return filterMessagesForUser(merged, deletedIds)
    })
  }

  async function resolveConversationIdFromUrl(
    sessionUser: { id: string },
    knownInboxId: string | null
  ): Promise<string | null> {
    if (isConversationUuidSegment(urlSegment)) {
      return urlSegment
    }
    if (knownInboxId) {
      return knownInboxId
    }

    if (isDemoUserId(sessionUser.id)) {
      return resolveDemoConversationIdFromSegment(urlSegment, sessionUser.id)
    }

    const normalized = normalizeProfileUsername(urlSegment)
    if (!normalized) return null

    const { data: prof } = await supabase
      .from("profiles")
      .select("id, username")
      .eq("username", normalized)
      .maybeSingle()

    if (!prof || prof.id === sessionUser.id) return null

    const result = await ensureDmConversation(supabase, sessionUser.id, prof.id)
    if (!result.ok) return null
    return result.conversationId
  }

  async function maybeCanonicalizeGroupDmUrl(
    details: { isGroup: boolean; otherProfile: any | null } | null
  ) {
    if (
      !isConversationUuidSegment(urlSegment) ||
      !details ||
      details.isGroup
    ) {
      return
    }
    const normalized = normalizeProfileUsername(details.otherProfile?.username ?? "")
    if (!normalized) return
    const target = buildDmThreadPath(normalized)
    const currentPath = `/messages/${urlSegment}`
    if (target !== currentPath) {
      router.replace(target, { scroll: false })
    }
  }

  async function runPostOpenSideEffects(
    userId: string,
    conversationId: string,
    cached: ConversationSessionSnapshot | null
  ) {
    const allowed = await isConversationParticipant(conversationId, userId)
    if (!allowed) {
      setPageAccess("unavailable")
      return
    }

    void markMessageNotificationsRead(userId)
    void markConversationMessagesSeen(userId, conversationId)

    const detailsPromise = fetchConversationDetails(userId, conversationId, {
      skipParticipantCheck: true,
    })

    if (cached?.messagesLoaded) {
      void syncNewerMessages(userId, conversationId, cached)
    }

    if (isConversationUuidSegment(urlSegment)) {
      const details = await detailsPromise
      await maybeCanonicalizeGroupDmUrl(details)
    }
  }

  async function init() {
    if (restoredFromCacheRef.current) {
      return
    }

    persistConversationCache()

    if (profileUser?.id && tryRestoreCachedConversation(profileUser)) {
      return
    }

    const sessionUser = isDemoSupabaseBlocked() && profileUser?.id
      ? profileUser
      : (
          await supabase.auth.getSession()
        ).data.session?.user ?? profileUser ?? null

    if (sessionUser?.id && tryRestoreCachedConversation(sessionUser)) {
      return
    }

    setPageAccess("loading")
    setActiveConversationId(null)

    if (!sessionUser) {
      setUser(null)
      setPageAccess("unauthenticated")
      router.push("/login")
      return
    }

    setUser(sessionUser)

    const inboxConversationId = peekInboxConversationId(urlSegment)
    const conversationId = await resolveConversationIdFromUrl(
      sessionUser,
      inboxConversationId
    )
    if (!conversationId) {
      setPageAccess("unavailable")
      return
    }

    consumeInboxConversationId(urlSegment)

    const allowed = await isConversationParticipant(
      conversationId,
      sessionUser.id
    )
    if (!allowed) {
      setPageAccess("unavailable")
      return
    }

    setActiveConversationId(conversationId)
    setPageAccess("allowed")

    setMessages([])
    setMessagesLoaded(false)
    setConversation(null)
    setParticipants([])
    setOtherUser(null)
    setInput("")
    setReplyTarget(null)
    setTradesById({})
    setPostsById({})
    userNearBottomRef.current = true
    prevLastMessageIdRef.current = null
    scrollAnchorRef.current = null

    const details = await fetchConversationDetails(
      sessionUser.id,
      conversationId
    )
    await loadMessages(sessionUser.id, conversationId)
    if (!isDemoSupabaseBlocked()) {
      void markMessageNotificationsRead(sessionUser.id)
      void markConversationMessagesSeen(sessionUser.id, conversationId)
    }
    await maybeCanonicalizeGroupDmUrl(details)
  }

  function resolveProvisionalConversationId(
    sessionUserId: string
  ): string | null {
    if (isConversationUuidSegment(urlSegment)) {
      return urlSegment
    }
    const inboxId = peekInboxConversationId(urlSegment)
    if (inboxId) return inboxId
    const byUrl = findConversationSessionByUrlSegment(sessionUserId, urlSegment)
    return byUrl?.conversationId ?? null
  }

  function tryRestoreCachedConversation(sessionUser: { id: string }): boolean {
    const provisionalId = resolveProvisionalConversationId(sessionUser.id)
    if (!provisionalId) return false

    const cached =
      readConversationSession(sessionUser.id, provisionalId) ??
      findConversationSessionByUrlSegment(sessionUser.id, urlSegment)

    if (!cached?.messagesLoaded) return false
    // Prior failed loads wrote messagesLoaded:true with []. Always refetch history.
    if (!cached.messages?.length) return false

    const conversationId = cached.conversationId || provisionalId
    consumeInboxConversationId(urlSegment)
    consumeConversationOpenFromInbox(conversationId)
    applyCachedConversation(cached, conversationId, sessionUser)
    restoredFromCacheRef.current = true
    void runPostOpenSideEffects(sessionUser.id, conversationId, cached)
    return true
  }

  useLayoutEffect(() => {
    scrollAnchorRef.current = null
    pendingSmoothScrollRef.current = false
    userNearBottomRef.current = true
    prevLastMessageIdRef.current = null

    restoredFromCacheRef.current = false
    persistConversationCacheRef.current()
    if (profileUser?.id && tryRestoreCachedConversation(profileUser)) {
      return
    }
  }, [urlSegment, profileUser?.id])

  useEffect(() => {
    void init()
    return () => {
      persistConversationCacheRef.current()
      if (scrollPersistTimerRef.current) {
        clearTimeout(scrollPersistTimerRef.current)
      }
    }
  }, [urlSegment, profileUser?.id])

  useEffect(() => {
    const uid = userIdRef.current
    const cid = conversationIdRef.current
    if (!uid || !cid || !messagesLoaded) return
    patchConversationSession(uid, cid, { draft: input, replyTarget })
  }, [input, replyTarget, messagesLoaded])

  async function fetchConversationDetails(
    currentUserId: string,
    conversationId: string,
    options?: { skipParticipantCheck?: boolean }
  ) {
    if (isDemoUserId(currentUserId)) {
      const demo = fetchDemoConversationDetails(currentUserId, conversationId)
      if (!demo) return null
      setConversation(demo.conversation)
      setParticipants(demo.participants)
      setOtherUser(demo.otherUser)
      conversationMetaRef.current = {
        conversation: demo.conversation,
        participants: demo.participants,
        otherUser: demo.otherUser,
      }
      const uid = userIdRef.current
      if (uid) {
        patchConversationSession(uid, conversationId, {
          conversation: demo.conversation,
          participants: demo.participants,
          otherUser: demo.otherUser,
        })
      }
      return {
        isGroup: demo.conversation.is_group === true,
        otherProfile: demo.otherUser,
      }
    }

    if (!options?.skipParticipantCheck) {
      if (!(await isConversationParticipant(conversationId, currentUserId))) {
        return null
      }
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

    conversationMetaRef.current = {
      conversation: convo || null,
      participants: data || [],
      otherUser: otherProfile || null,
    }

    const uid = userIdRef.current
    if (uid) {
      patchConversationSession(uid, conversationId, {
        conversation: convo || null,
        participants: data || [],
        otherUser: otherProfile || null,
      })
    }

    return {
      isGroup: convo?.is_group === true,
      otherProfile: otherProfile ?? null,
    }
  }

  function queueSmoothScrollToBottom() {
    userNearBottomRef.current = true
    pendingSmoothScrollRef.current = true
  }

  async function loadMessages(currentUserId: string, conversationId: string) {
    if (isDemoUserId(currentUserId)) {
      const fetched = fetchDemoConversationMessages(conversationId, currentUserId)
      setMessages(fetched as typeof messages)
      setMessagesLoaded(true)
      const uid = userIdRef.current
      if (uid) {
        updateConversationMessages(uid, conversationId, () => fetched)
      }
      queueSmoothScrollToBottom()
      return
    }

    if (!(await isConversationParticipant(conversationId, currentUserId))) {
      setMessagesLoaded(true)
      return
    }

    console.log("[dm-thread-load]", {
      urlSegment: urlSegmentRef.current,
      conversationIdFromUrl: urlSegmentRef.current,
      conversationIdUsedInQuery: conversationId,
      query: {
        table: "messages",
        select: "DM_MESSAGE_SELECT (+ fallback without sender_anonymized)",
        filter: `conversation_id=eq.${conversationId}`,
        order: "created_at ascending",
      },
    })

    const { data: fetched, error } = await queryDmMessages((select) =>
      supabase
        .from("messages")
        .select(select)
        .eq("conversation_id", conversationId)
        .order("created_at", { ascending: true })
    )

    console.log("[dm-thread-load] result", {
      conversationIdUsedInQuery: conversationId,
      rowCount: fetched?.length ?? 0,
      firstRow: fetched?.[0] ?? null,
      supabaseError: error?.message ?? null,
      supabaseErrorCode: (error as { code?: string } | null)?.code ?? null,
    })

    if (error) {
      console.error("[dm-thread-load] query failed", error)
      setMessages([])
      setMessagesLoaded(true)
      return
    }

    const deletedIds = await fetchConversationDeletedMessageIds(
      currentUserId,
      (fetched || []).map((message) => String(message.id))
    )

    const filteredMessages = filterMessagesForUser(fetched || [], deletedIds)
    const sorted = sortMessagesByCreatedAt(filteredMessages)

    setMessages(sorted)
    prevLastMessageIdRef.current = null
    scrollAnchorRef.current = {
      conversationId,
      lastMessageId: computeNewestMessage(sorted).id,
    }
    setMessagesLoaded(true)

    const newest = computeNewestMessage(sorted)
    const meta = conversationMetaRef.current
    writeConversationSession(currentUserId, conversationId, {
      urlSegment: urlSegmentRef.current,
      messages: sorted,
      messagesLoaded: true,
      conversation: meta.conversation,
      participants: meta.participants,
      otherUser: meta.otherUser,
      newestMessageId: newest.id,
      newestTimestamp: newest.timestamp,
      unreadCount: 0,
      scrollTop: 0,
      wasAtBottom: true,
      draft: "",
      replyTarget: null,
      tradesById: tradesByIdRef.current,
      postsById: postsByIdRef.current,
    })
  }

  function removeImage() {
    setSelectedFile(null)
    setSelectedImage(null)
    setPreviewUrl(null)
    dmImageCrop.resetFileInput()
  }

  function handleImageChange(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    dmImageCrop.handleFileSelected(file)
  }

  function handleFileChange(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    groupImageCrop.handleFileSelected(file)
  }

  async function sendMessage() {
    if (isDemoModeActive()) {
      requestDemoSignup("comment")
      return
    }
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
      showPopup(dmSendFeedback(sendErr))
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

    queueSmoothScrollToBottom()
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
    if (isDemoModeActive()) {
      requestDemoSignup("comment")
      return
    }
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
      showPopup(dmSendFeedback(tradeSendErr, "Share Failed"))
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

    queueSmoothScrollToBottom()
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
    setMessagesWithCache((prev) => prev.filter((m) => m.id !== message.id))
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
    setMessagesWithCache((prev) =>
      prev.map((m) =>
        m.id === message.id ? { ...m, deleted_for_everyone: true } : m
      )
    )
    setActiveMenuId(null)
  }

  const peerDeleted = isDirectConversationPeerDeleted(
    Boolean(conversation?.is_group),
    otherUser?.username,
    messages.length > 0
  )
  const title = conversation?.is_group
    ? conversation?.name || "Group Chat"
    : peerDeleted
      ? DELETED_USER_LABEL
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
      <ImageCropModal
        open={dmImageCrop.cropSourceFile != null}
        file={dmImageCrop.cropSourceFile}
        preset="content"
        onCancel={dmImageCrop.handleCropCancel}
        onSave={dmImageCrop.handleCropSave}
      />
      <ImageCropModal
        open={groupImageCrop.cropSourceFile != null}
        file={groupImageCrop.cropSourceFile}
        preset="avatar"
        onCancel={groupImageCrop.handleCropCancel}
        onSave={groupImageCrop.handleCropSave}
      />
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
            <p className="text-gray-300">{LOADING_COPY.conversation}</p>
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
                ) : otherUser?.id && !peerDeleted ? (
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
            onScroll={handleMessagesScroll}
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
                    className="my-2 whitespace-pre-wrap break-words text-center text-sm text-gray-400"
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

              if (message.type === "trade") {
                return (
                  <Fragment key={message.id}>
                    {showDateDivider ? (
                      <ConversationDateDivider label={dateDividerLabel} />
                    ) : null}
                    <div className={rowClass}>
                      {showName ? (
                        <DmSenderNameLine message={message} />
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
                        initialTrade={
                          tradesById[
                            dmTradePreviewCacheKey(message.trade_id) ?? ""
                          ] ?? null
                        }
                        onTradeLoaded={(trade) =>
                          handleTradePreviewLoaded(String(message.trade_id), trade)
                        }
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

              if (message.type === STORY_REPLY_MESSAGE_TYPE) {
                return (
                  <Fragment key={message.id}>
                    {showDateDivider ? (
                      <ConversationDateDivider label={dateDividerLabel} />
                    ) : null}
                    <div className={rowClass}>
                      {showName ? (
                        <DmSenderNameLine message={message} />
                      ) : null}
                      <StoryReplyMessageBubble
                        message={message}
                        isMe={isMe}
                        userId={user?.id}
                        activeMenuId={activeMenuId}
                        setActiveMenuId={setActiveMenuId}
                        deleteForMe={deleteForMe}
                        deleteForEveryone={deleteForEveryone}
                        onReply={startReplyToMessage}
                        onJumpToParent={scrollToDmMessage}
                        onReplyUnavailable={notifyReplyUnavailable}
                        parentMessage={parentMessage}
                        onMediaLoad={bumpMessageLayout}
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

              if (
                message.type === "post" ||
                message.type === "profile_post" ||
                message.type === "achievement_post" ||
                message.type === "reel"
              ) {
                return (
                  <Fragment key={message.id}>
                    {showDateDivider ? (
                      <ConversationDateDivider label={dateDividerLabel} />
                    ) : null}
                    <div className={rowClass}>
                      {showName ? (
                        <DmSenderNameLine message={message} />
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
                        initialPost={
                          postsById[dmPostPreviewCacheKey(message) ?? ""] ?? null
                        }
                        onPostLoaded={(post) => {
                          const key = dmPostPreviewCacheKey(message)
                          if (key) handlePostPreviewLoaded(key, post)
                        }}
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
                    {showName ? (
                      <DmSenderNameLine message={message} />
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
                                    onLoad={bumpMessageLayout}
                                    onError={bumpMessageLayout}
                                  />
                                </button>
                              ) : null}
                              {message.content ? (
                                <p
                                  className={`whitespace-pre-wrap break-words ${
                                    message.image_url ? "mt-2" : undefined
                                  }`}
                                >
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
                    <ProfileAvatarImg
                      src={m.profiles?.avatar_url}
                      className="h-6 w-6"
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
                    <ProfileAvatarImg
                      src={u.avatar_url}
                      className="h-8 w-8 shrink-0"
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