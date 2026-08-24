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
import { ChevronLeft } from "lucide-react"
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
import { createDirectMessagePush } from "@/lib/createDirectMessagePush"
import {
  createOptimisticTempId,
} from "@/lib/optimisticMutation"
import {
  mergeRealtimeMessageIntoList,
  markOptimisticMessageFailed,
  replaceOptimisticMessage,
} from "@/lib/optimisticMessage"
import SyncStatusText from "@/app/components/ui/SyncStatusText"
import { MICRO } from "@/lib/microInteractions"
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
import StorageImage from "@/app/components/ui/StorageImage"
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
import { markMessageNotificationsRead } from "@/lib/messageNotificationReadSync"
import {
  areConversationPreviewsReady,
  filterMessagesForUser,
  isScrollNearBottom,
  mergeMessageLists,
  sortMessagesByCreatedAt,
  computeNewestMessage,
} from "@/lib/conversationMessageUtils"
import {
  beginThreadScrollOpen,
  captureThreadPaginationAnchor,
  getThreadScrollSession,
  isThreadNearBottom,
  requestThreadJumpToNewest,
  requestThreadLocalSendScroll,
  restoreThreadPaginationAnchor,
  runThreadScrollLayoutPass,
  scrollThreadContainerToBottom,
  shouldPinThreadOnKeyboard,
  updateThreadPinnedBottomIntent,
} from "@/lib/conversationThreadScroll"
import { isLastMessageInDom } from "@/lib/conversationScroll"
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
import { mapProjectedRows } from "@/lib/supabaseProjectedQuery"
import ConversationSettingsModal from "@/app/components/messages/ConversationSettingsModal"
import SharedMediaModal from "@/app/components/messages/SharedMediaModal"
import {
  fetchConversationNotificationsEnabled,
  setConversationNotificationsEnabled,
} from "@/lib/conversationMemberPreferences"
import { ConfirmModal } from "@/app/components/ui"
import {
  fetchDmBlockStatus,
  setDmUserBlocked,
  type DmBlockStatus,
} from "@/lib/conversationBlocks"
import { clearMessagesInboxSessionsForUser } from "@/lib/messagesInboxSessionCache"
import { useIsNativeIos } from "@/lib/useIsNativeIos"
import { useNativeIosKeyboardInset } from "@/lib/useNativeIosKeyboardInset"
import { isBackendV2Enabled } from "@/lib/backendV2/flags"
import {
  applyConversationThreadBootstrap,
  type ConversationThreadApplyTarget,
} from "@/lib/backendV2/conversationThreadBootstrapApply"
import {
  ConversationThreadLoadError,
  ConversationThreadStaleError,
  loadConversationThreadBootstrap,
  readConversationThreadNextCursor,
} from "@/lib/backendV2/conversationThreadBootstrapRepository"
import {
  conversationThreadCacheKey,
  readConversationThreadCache,
} from "@/lib/backendV2/conversationThreadBootstrapCache"
import { readConversationThreadHeaderSeed } from "@/lib/backendV2/conversationThreadInboxSeed"
import { mapThreadBootstrapMessagesToWire } from "@/lib/backendV2/conversationThreadContracts"
import {
  beginThreadOpenLifecycle,
  markThreadReadInFlight,
  releaseThreadReadInFlight,
  resolveThreadBootstrapMarkRead,
} from "@/lib/backendV2/conversationThreadReadLifecycle"

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
      <span className="shrink-0 text-[11px] font-medium tracking-wide text-gray-400">
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
      className={`mt-1 px-1 text-[11px] leading-none text-gray-400 ${
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
  const initialPostRef = useRef(initialPost)
  const onPostLoadedRef = useRef(onPostLoaded)
  initialPostRef.current = initialPost
  onPostLoadedRef.current = onPostLoaded
  const isProfileShare =
    message.type === "profile_post" || Boolean(message.profile_post_id)
  const isAchievementShare =
    message.type === "achievement_post" || Boolean(message.achievement_post_id)
  const isReelShare =
    message.type === "reel" || Boolean(message.reel_id)

  useEffect(() => {
    const cachedPost = initialPostRef.current
    if (cachedPost) {
      setPost(cachedPost)
      setPostLoading(false)
      return
    }

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
      setPostLoading(true)
      setPost(null)
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
          onPostLoadedRef.current?.(loaded)
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
      setPostLoading(true)
      setPost(null)
      ;(async () => {
        const { data } = await supabase
          .from("achievement_posts")
          .select(FEED_ACHIEVEMENT_POSTS_SELECT)
          .eq("id", achievementPostId)
          .maybeSingle()
        if (!cancelled) {
          setPost(data ?? null)
          setPostLoading(false)
          onPostLoadedRef.current?.(data ?? null)
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
          onPostLoadedRef.current?.(data ?? null)
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
        onPostLoadedRef.current?.(data ?? null)
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
                variant="message"
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
              <StorageImage
                src={storyImageUrl}
                originalSrc={storyImageUrl}
                preset="message-story-thumb"
                fallbackToOriginal={false}
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
  const messagePageSize = 50
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const { user: profileUser } = useUserProfile()
  const nativeIos = useIsNativeIos()
  const params = useParams()
  const router = useRouter()
  const urlSegment = params.id as string
  const [activeConversationId, setActiveConversationId] = useState<string | null>(
    null
  )

  const [messages, setMessages] = useState<any[]>([])
  const sharedMediaRefreshKey = useMemo(() => {
    for (let index = messages.length - 1; index >= 0; index -= 1) {
      const message = messages[index]
      if (message?.deleted_for_everyone) continue
      const storyImage =
        message?.type === STORY_REPLY_MESSAGE_TYPE
          ? decodeStoryReplyContent(message.content)?.story_image_url
          : null
      if (
        message?.image_url ||
        message?.trade_id ||
        message?.post_id ||
        message?.profile_post_id ||
        message?.reel_id ||
        storyImage
      ) {
        return String(message.id)
      }
    }
    return null
  }, [messages])
  const [messagesLoaded, setMessagesLoaded] = useState(false)
  const [hasOlderMessages, setHasOlderMessages] = useState(false)
  const [loadingOlderMessages, setLoadingOlderMessages] = useState(false)
  const [messagesLoadError, setMessagesLoadError] = useState<string | null>(null)
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
  const [showConversationSettings, setShowConversationSettings] =
    useState(false)
  const [groupName, setGroupName] = useState("")
  const [groupImage, setGroupImage] = useState<File | null>(null)
  const [savingGroupSettings, setSavingGroupSettings] = useState(false)
  const [groupSettingsSuccess, setGroupSettingsSuccess] = useState("")
  const [showAddMembers, setShowAddMembers] = useState(false)
  const [notificationsEnabled, setNotificationsEnabled] = useState(true)
  const [notificationsSaving, setNotificationsSaving] = useState(false)
  const [pinSaving, setPinSaving] = useState(false)
  const [leaveBusy, setLeaveBusy] = useState(false)
  const [confirmLeaveOpen, setConfirmLeaveOpen] = useState(false)
  const [showSharedMedia, setShowSharedMedia] = useState(false)
  const [dmBlockStatus, setDmBlockStatus] = useState<DmBlockStatus | null>(null)
  const [blockStatusLoading, setBlockStatusLoading] = useState(false)
  const [blockSaving, setBlockSaving] = useState(false)
  const [blockConfirmation, setBlockConfirmation] = useState<boolean | null>(
    null
  )
  const [allUsers, setAllUsers] = useState<any[]>([])
  const [selectedUsers, setSelectedUsers] = useState<any[]>([])
  const [showTradePicker, setShowTradePicker] = useState(false)
  const [lightboxImageUrl, setLightboxImageUrl] = useState<string | null>(null)
  const [trades, setTrades] = useState<any[]>([])
  const [tradesById, setTradesById] = useState<Record<string, any>>({})
  const [postsById, setPostsById] = useState<Record<string, any>>({})
  const [messageLayoutGeneration, setMessageLayoutGeneration] = useState(0)
  const [threadScrollRevealReady, setThreadScrollRevealReady] = useState(false)
  const [newMessagesBelowCount, setNewMessagesBelowCount] = useState(0)
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

  useEffect(() => {
    if (!previewUrl?.startsWith("blob:")) return
    return () => URL.revokeObjectURL(previewUrl)
  }, [previewUrl])

  const scrollRef = useRef<HTMLDivElement>(null)
  const bottomAnchorRef = useRef<HTMLDivElement>(null)
  const userIdRef = useRef<string | null>(null)
  const conversationIdRef = useRef<string | null>(null)

  const keepComposerVisibleAboveKeyboard = useCallback(() => {
    const el = scrollRef.current
    const uid = userIdRef.current
    const cid = conversationIdRef.current
    if (!el || !uid || !cid) return
    const session = getThreadScrollSession(uid, cid)
    if (!shouldPinThreadOnKeyboard(session)) return
    scrollThreadContainerToBottom(el, "auto")
  }, [])

  useNativeIosKeyboardInset(nativeIos, {
    htmlClass: "tt-ios-dm",
    onKeyboardShow: keepComposerVisibleAboveKeyboard,
  })

  const messagesChannelRef = useRef<ReturnType<typeof supabase.channel> | null>(
    null
  )
  const userNearBottomRef = useRef(true)
  const threadScrollOpenTokenRef = useRef(0)
  const paginationAnchorRef = useRef<ReturnType<typeof captureThreadPaginationAnchor>>(null)
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
  const threadLoadGenerationRef = useRef(0)
  const threadOpenIdRef = useRef(0)
  const threadBootstrapOwnedReadRef = useRef(false)
  const messagesRef = useRef<any[]>([])
  const loadOlderMessagesRef = useRef<() => void>(() => {})
  const loadingOlderMessagesRef = useRef(false)

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
    setHasOlderMessages(cached.hasOlderMessages ?? false)
    setMessagesLoaded(true)
    setMessagesLoadError(null)
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
    beginThreadScrollOpen(
      getThreadScrollSession(sessionUser.id, conversationId),
      sessionUser.id,
      conversationId,
      threadScrollOpenTokenRef.current
    )
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
    void import("@/lib/messagingActiveContext").then(
      ({ setActiveConversationId: setMessagingActiveConversation }) => {
        setMessagingActiveConversation(activeConversationId)
      }
    )
    return () => {
      void import("@/lib/messagingActiveContext").then(
        ({ setActiveConversationId: setMessagingActiveConversation }) => {
          setMessagingActiveConversation(null)
        }
      )
    }
  }, [activeConversationId])

  useEffect(() => {
    messagesRef.current = messages
  }, [messages])

  useEffect(() => {
    if (!user?.id || !activeConversationId || pageAccess !== "allowed") return
    if (isBackendV2Enabled("messageThreads")) return
    if (threadBootstrapOwnedReadRef.current) return
    void import("@/lib/notificationReadSync").then(
      ({ markNotificationsReadForTarget }) => {
        void markNotificationsReadForTarget(user.id, {
          kind: "conversation",
          conversationId: activeConversationId,
        })
      }
    )
    void (async () => {
      try {
        const { supabaseBearerHeaders } = await import(
          "@/lib/supabaseBearerFetch"
        )
        const authHeaders = await supabaseBearerHeaders()
        await fetch("/api/notifications/mark-read-target", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            ...authHeaders,
          },
          body: JSON.stringify({
            conversationId: activeConversationId,
            markConversationRead: false,
          }),
        })
      } catch {
        /* ignore — client-side notification read still ran */
      }
    })()
    void import("@/lib/clearDeliveredConversationNotifications").then(
      ({ clearDeliveredConversationNotifications }) => {
        void clearDeliveredConversationNotifications(activeConversationId)
      }
    )
  }, [user?.id, activeConversationId, pageAccess])

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
      hasOlderMessages,
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
    hasOlderMessages,
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

    const uid = userIdRef.current
    const cid = conversationIdRef.current
    const nearBottom = isThreadNearBottom(el)
    userNearBottomRef.current = nearBottom
    if (uid && cid) {
      updateThreadPinnedBottomIntent(getThreadScrollSession(uid, cid), nearBottom)
    }

    if (el.scrollTop < 80) {
      loadOlderMessagesRef.current()
    }

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
              const messageId = raw.id
              const { data } = await queryDmMessages((select) =>
                supabase
                  .from("messages")
                  .select(select)
                  .eq("id", messageId)
                  .maybeSingle()
                  .overrideTypes<Record<string, unknown> | null, { merge: false }>()
              )
              if (data) row = data
            }
            setMessagesWithCache((prev) => {
              const merged = mergeRealtimeMessageIntoList(
                prev,
                row,
                userIdRef.current
              )
              return sortMessagesByCreatedAt(merged)
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
    const anchor = paginationAnchorRef.current
    const el = scrollRef.current
    if (anchor && el) {
      restoreThreadPaginationAnchor(el, anchor)
      paginationAnchorRef.current = null
    }
  }, [messages])

  useLayoutEffect(() => {
    if (!messagesLoaded || !activeConversationId || !user?.id) return
    const el = scrollRef.current
    if (!el) return

    const lastMsg = messages[messages.length - 1]
    const lastId = lastMsg ? String(lastMsg.id) : null
    const previewsReady = areConversationPreviewsReady(
      messages,
      tradesById,
      postsById,
      dmTradePreviewCacheKey,
      dmPostPreviewCacheKey
    )
    const lastInDom = isLastMessageInDom(lastId, el, lastMsg)
    const session = getThreadScrollSession(user.id, activeConversationId)
    const reducedMotion =
      typeof window !== "undefined" &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches

    const { revealReady } = runThreadScrollLayoutPass({
      session,
      container: el,
      messagesLoaded,
      newestMessageId: lastId,
      previewsReady,
      lastMessageInDom: lastInDom,
      prefersReducedMotion: reducedMotion,
    })

    setThreadScrollRevealReady(revealReady)
    setNewMessagesBelowCount(session.newMessagesBelow)
  }, [
    messages,
    messagesLoaded,
    activeConversationId,
    user?.id,
    tradesById,
    postsById,
    messageLayoutGeneration,
  ])

  useEffect(() => {
    if (!messagesLoaded || !activeConversationId || !user?.id) return
    const el = scrollRef.current
    if (!el) return

    const session = getThreadScrollSession(user.id, activeConversationId)
    if (session.phase !== "stabilizing" && session.phase !== "committed") return
    if (!session.pinnedBottomIntent) return

    const observer = new ResizeObserver(() => {
      if (!session.pinnedBottomIntent || !isThreadNearBottom(el)) return
      scrollThreadContainerToBottom(el, "auto")
      if (session.phase === "stabilizing") {
        const previewsReady = areConversationPreviewsReady(
          messagesRef.current,
          tradesByIdRef.current,
          postsByIdRef.current,
          dmTradePreviewCacheKey,
          dmPostPreviewCacheKey
        )
        const lastMsg = messagesRef.current[messagesRef.current.length - 1]
        const lastId = lastMsg ? String(lastMsg.id) : null
        const lastInDom = isLastMessageInDom(lastId, el, lastMsg)
        const { revealReady } = runThreadScrollLayoutPass({
          session,
          container: el,
          messagesLoaded: true,
          newestMessageId: lastId,
          previewsReady,
          lastMessageInDom: lastInDom,
        })
        setThreadScrollRevealReady(revealReady)
      }
    })

    observer.observe(el)
    return () => observer.disconnect()
  }, [messagesLoaded, activeConversationId, user?.id])

  function jumpToNewestMessages() {
    const uid = userIdRef.current
    const cid = conversationIdRef.current
    const el = scrollRef.current
    if (!uid || !cid || !el) return
    requestThreadJumpToNewest(getThreadScrollSession(uid, cid))
    const reducedMotion =
      typeof window !== "undefined" &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches
    runThreadScrollLayoutPass({
      session: getThreadScrollSession(uid, cid),
      container: el,
      messagesLoaded: true,
      newestMessageId: messages[messages.length - 1]
        ? String(messages[messages.length - 1]!.id)
        : null,
      previewsReady: true,
      lastMessageInDom: true,
      prefersReducedMotion: reducedMotion,
    })
    setThreadScrollRevealReady(true)
    setNewMessagesBelowCount(0)
  }

  useEffect(() => {
    if (!isTyping) return
    const timer = setTimeout(() => setIsTyping(false), 1200)
    return () => clearTimeout(timer)
  }, [isTyping, input])

  useEffect(() => {
    setGroupName(conversation?.name || "")
  }, [conversation?.name])

  useEffect(() => {
    if (isBackendV2Enabled("messageThreads")) return
    if (
      !activeConversationId ||
      !user?.id ||
      conversation?.is_group !== false ||
      isDemoSupabaseBlocked()
    ) {
      setDmBlockStatus(null)
      setBlockStatusLoading(false)
      return
    }

    let cancelled = false
    setBlockStatusLoading(true)
    void fetchDmBlockStatus(activeConversationId).then((result) => {
      if (cancelled) return
      setBlockStatusLoading(false)
      if (result.ok) {
        setDmBlockStatus(result.status)
      }
    })

    return () => {
      cancelled = true
    }
  }, [activeConversationId, conversation?.is_group, user?.id])

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

    // Bounded catch-up: page newer messages instead of an unlimited SELECT.
    const SYNC_PAGE_SIZE = messagePageSize
    const SYNC_MAX_PAGES = 20
    const incoming: any[] = []
    let cursorTs = cached.newestTimestamp
    let cursorId = cached.newestMessageId ?? null

    for (let page = 0; page < SYNC_MAX_PAGES; page++) {
      const pageCursorTs = cursorTs
      const pageCursorId = cursorId
      const { data: batch } = await queryDmMessages((select) => {
        let query = supabase
          .from("messages")
          .select(select)
          .eq("conversation_id", conversationId)
          .order("created_at", { ascending: true })
          .order("id", { ascending: true })
          .limit(SYNC_PAGE_SIZE)
        query = pageCursorId
          ? query.or(
              `created_at.gt.${pageCursorTs},and(created_at.eq.${pageCursorTs},id.gt.${pageCursorId})`
            )
          : query.gt("created_at", pageCursorTs)
        return query.overrideTypes<Record<string, unknown>[], { merge: false }>()
      })

      if (!batch?.length) break
      const batchRows = mapProjectedRows(batch, (row) => row)
      incoming.push(...batchRows)
      const last = batchRows[batchRows.length - 1]
      cursorTs = String(last.created_at)
      cursorId = String(last.id)
      if (batch.length < SYNC_PAGE_SIZE) break
    }

    if (!incoming.length) return

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
    if (isBackendV2Enabled("messageThreads")) {
      if (cached?.messagesLoaded) {
        const generation = threadLoadGenerationRef.current
        void loadConversationThreadBootstrap(supabase, userId, {
          conversationId,
          markRead: false,
          caller: "thread-revalidate",
        })
          .then((result) => {
            if (generation !== threadLoadGenerationRef.current) return
            applyConversationThreadBootstrap(
              result.bootstrap,
              userId,
              conversationId,
              buildThreadApplyTarget(urlSegmentRef.current),
              {
                skipReadSideEffects: true,
                existingMessages: messagesRef.current,
              }
            )
          })
          .catch(() => {
            /* preserve cached messages on revalidation failure */
          })
      }
      return
    }

    const allowed = await isConversationParticipant(conversationId, userId)
    if (!allowed) {
      setPageAccess("unavailable")
      return
    }

    void markMessageNotificationsRead(userId, "thread-open")
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

  function buildThreadApplyTarget(segment: string): ConversationThreadApplyTarget {
    return {
      setConversation,
      setParticipants,
      setOtherUser,
      setNotificationsEnabled,
      setDmBlockStatus,
      setBlockStatusLoading,
      setMessages,
      setHasOlderMessages,
      setMessagesLoaded,
      setMessagesLoadError,
      conversationMetaRef,
      patchConversationSession,
      urlSegment: segment,
    }
  }

  function applyInboxHeaderSeed(
    seed: NonNullable<ReturnType<typeof readConversationThreadHeaderSeed>>
  ) {
    setConversation(seed.conversation)
    setParticipants(seed.participants)
    setOtherUser(seed.otherUser)
    setNotificationsEnabled(seed.notificationsEnabled)
    conversationMetaRef.current = {
      conversation: seed.conversation,
      participants: seed.participants,
      otherUser: seed.otherUser,
    }
  }

  async function initThreadV2(sessionUser: { id: string }) {
    const generation = ++threadLoadGenerationRef.current
    threadBootstrapOwnedReadRef.current = false
    if (!threadOpenIdRef.current) {
      threadOpenIdRef.current = beginThreadOpenLifecycle(sessionUser.id)
    }

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

    const headerSeed = readConversationThreadHeaderSeed({
      userId: sessionUser.id,
      conversationId,
      urlSegment,
    })
    if (headerSeed) {
      applyInboxHeaderSeed(headerSeed)
    }

    setActiveConversationId(conversationId)
    beginThreadScrollOpen(
      getThreadScrollSession(sessionUser.id, conversationId),
      sessionUser.id,
      conversationId,
      threadScrollOpenTokenRef.current
    )
    setPageAccess("allowed")
    setUser(sessionUser)

    const cacheKey = conversationThreadCacheKey({
      userId: sessionUser.id,
      conversationId,
    })
    const cachedBootstrap = readConversationThreadCache(cacheKey)
    const previousUnread =
      headerSeed?.unreadCount ??
      cachedBootstrap?.data.unread_count ??
      0
    if (cachedBootstrap?.data.messages.length) {
      applyConversationThreadBootstrap(
        cachedBootstrap,
        sessionUser.id,
        conversationId,
        buildThreadApplyTarget(urlSegment),
        { skipReadSideEffects: true }
      )
    } else {
      setMessages([])
      setMessagesLoaded(false)
      setMessagesLoadError(null)
      if (!headerSeed) {
        setConversation(null)
        setParticipants([])
        setOtherUser(null)
      }
      setInput("")
      setReplyTarget(null)
      setTradesById({})
      setPostsById({})
      userNearBottomRef.current = true
    }

    const openId = threadOpenIdRef.current
    const markRead = resolveThreadBootstrapMarkRead({
      viewerId: sessionUser.id,
      conversationId,
      openId,
      mode: "intentional-open",
      authenticated: !isDemoSupabaseBlocked(),
    })
    if (markRead) {
      markThreadReadInFlight(sessionUser.id, conversationId, openId)
    }

    try {
      const result = await loadConversationThreadBootstrap(
        supabase,
        sessionUser.id,
        {
          conversationId,
          markRead,
          caller: "thread-open",
        },
        { loadGeneration: generation, expectedGeneration: generation }
      )

      if (generation !== threadLoadGenerationRef.current) return

      if (result.bootstrap.data.mark_read.applied) {
        threadBootstrapOwnedReadRef.current = true
      } else if (markRead) {
        releaseThreadReadInFlight(sessionUser.id, conversationId, openId)
      }

      applyConversationThreadBootstrap(
        result.bootstrap,
        sessionUser.id,
        conversationId,
        buildThreadApplyTarget(urlSegment),
        {
          existingMessages: messagesRef.current,
          previousConversationUnread: previousUnread,
          openId,
        }
      )

      const details = {
        isGroup: result.bootstrap.data.conversation.is_group,
        otherProfile: conversationMetaRef.current?.otherUser ?? null,
      }
      await maybeCanonicalizeGroupDmUrl(details)
    } catch (err) {
      if (err instanceof ConversationThreadStaleError) return
      if (generation !== threadLoadGenerationRef.current) return
      if (cachedBootstrap?.data.messages.length) return
      console.error("[dm-thread-v2] bootstrap failed", err)
      setMessagesLoadError("Couldn't load messages. Please try again.")
      setMessagesLoaded(true)
      if (!headerSeed) {
        setPageAccess("unavailable")
      }
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

    if (isBackendV2Enabled("messageThreads") && !isDemoSupabaseBlocked()) {
      await initThreadV2(sessionUser)
      return
    }

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
    beginThreadScrollOpen(
      getThreadScrollSession(sessionUser.id, conversationId),
      sessionUser.id,
      conversationId,
      threadScrollOpenTokenRef.current
    )
    setPageAccess("allowed")

    setMessages([])
    setMessagesLoaded(false)
    setMessagesLoadError(null)
    setConversation(null)
    setParticipants([])
    setOtherUser(null)
    setInput("")
    setReplyTarget(null)
    setTradesById({})
    setPostsById({})
    userNearBottomRef.current = true

    const details = await fetchConversationDetails(
      sessionUser.id,
      conversationId
    )
    await loadMessages(sessionUser.id, conversationId)
    if (!isDemoSupabaseBlocked()) {
      void markMessageNotificationsRead(sessionUser.id, "thread-open")
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
    threadScrollOpenTokenRef.current += 1
    setThreadScrollRevealReady(false)
    setNewMessagesBelowCount(0)
    userNearBottomRef.current = true
    paginationAnchorRef.current = null

    restoredFromCacheRef.current = false
    threadBootstrapOwnedReadRef.current = false
    if (profileUser?.id) {
      threadOpenIdRef.current = beginThreadOpenLifecycle(profileUser.id)
    }
    threadLoadGenerationRef.current += 1
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
      void fetchConversationNotificationsEnabled(
        currentUserId,
        conversationId
      ).then(setNotificationsEnabled)
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
      .select("id, is_group, name, avatar_url, is_pinned")
      .eq("id", conversationId)
      .maybeSingle()

    setConversation(convo || null)

    const notifEnabled = await fetchConversationNotificationsEnabled(
      currentUserId,
      conversationId
    )
    setNotificationsEnabled(notifEnabled)

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

  function requestScrollAfterLocalSend() {
    const uid = userIdRef.current
    const cid = conversationIdRef.current
    if (!uid || !cid) return
    userNearBottomRef.current = true
    requestThreadLocalSendScroll(getThreadScrollSession(uid, cid))
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
      beginThreadScrollOpen(
        getThreadScrollSession(currentUserId, conversationId),
        currentUserId,
        conversationId,
        threadScrollOpenTokenRef.current
      )
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
        .order("created_at", { ascending: false })
        .order("id", { ascending: false })
        .limit(messagePageSize + 1)
        .overrideTypes<Record<string, unknown>[], { merge: false }>()
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
      setMessagesLoadError("Couldn't load messages. Please try again.")
      setMessagesLoaded(true)
      return
    }

    const fetchedPage = mapProjectedRows(
      (fetched || []).slice(0, messagePageSize),
      (row) => row
    )
    const pageHasOlder = (fetched?.length ?? 0) > messagePageSize
    const deletedIds = await fetchConversationDeletedMessageIds(
      currentUserId,
      fetchedPage.map((message) => String(message.id))
    )

    const filteredMessages = filterMessagesForUser(fetchedPage, deletedIds)
    const sorted = sortMessagesByCreatedAt(filteredMessages)

    setMessages(sorted)
    setHasOlderMessages(pageHasOlder)
    setMessagesLoadError(null)
    beginThreadScrollOpen(
      getThreadScrollSession(currentUserId, conversationId),
      currentUserId,
      conversationId,
      threadScrollOpenTokenRef.current
    )
    setMessagesLoaded(true)

    const newest = computeNewestMessage(sorted)
    const meta = conversationMetaRef.current
    writeConversationSession(currentUserId, conversationId, {
      urlSegment: urlSegmentRef.current,
      messages: sorted,
      messagesLoaded: true,
      hasOlderMessages: pageHasOlder,
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

  async function loadOlderMessages() {
    if (loadingOlderMessagesRef.current || !hasOlderMessages) return
    const currentUserId = userIdRef.current
    const conversationId = conversationIdRef.current
    const oldest = messages[0]
    const el = scrollRef.current
    if (!currentUserId || !conversationId || !oldest?.created_at || !oldest?.id) return

    loadingOlderMessagesRef.current = true
    setLoadingOlderMessages(true)
    if (el) {
      paginationAnchorRef.current = captureThreadPaginationAnchor(el)
    }
    try {
      if (isBackendV2Enabled("messageThreads") && !isDemoSupabaseBlocked()) {
        const cursor =
          readConversationThreadNextCursor(currentUserId, conversationId) ??
          `${oldest.created_at}|${oldest.id}`
        const result = await loadConversationThreadBootstrap(
          supabase,
          currentUserId,
          {
            conversationId,
            cursor,
            markRead: false,
            caller: "thread-pagination",
          }
        )
        const wireMessages = mapThreadBootstrapMessagesToWire(
          result.bootstrap.data.messages
        )
        setHasOlderMessages(result.bootstrap.data.has_more_messages)
        patchConversationSession(currentUserId, conversationId, {
          hasOlderMessages: result.bootstrap.data.has_more_messages,
          messages: sortMessagesByCreatedAt(wireMessages),
        })
        setMessagesWithCache((current) => {
          if (wireMessages.length >= current.length + 1) {
            return sortMessagesByCreatedAt(wireMessages)
          }
          return mergeMessageLists(wireMessages, current)
        })
        return
      }

      const cursor = `created_at.lt.${oldest.created_at},and(created_at.eq.${oldest.created_at},id.lt.${oldest.id})`
      const { data: fetched, error } = await queryDmMessages((select) =>
        supabase
          .from("messages")
          .select(select)
          .eq("conversation_id", conversationId)
          .or(cursor)
          .order("created_at", { ascending: false })
          .order("id", { ascending: false })
          .limit(messagePageSize + 1)
          .overrideTypes<Record<string, unknown>[], { merge: false }>()
      )
      if (error) {
        console.error("[dm-thread-load-older] query failed", error)
        return
      }

      const fetchedPage = mapProjectedRows(
        (fetched || []).slice(0, messagePageSize),
        (row) => row
      )
      const deletedIds = await fetchConversationDeletedMessageIds(
        currentUserId,
        fetchedPage.map((message) => String(message.id))
      )
      const older = sortMessagesByCreatedAt(
        filterMessagesForUser(fetchedPage, deletedIds)
      )
      const nextHasOlder = (fetched?.length ?? 0) > messagePageSize
      setHasOlderMessages(nextHasOlder)
      patchConversationSession(currentUserId, conversationId, {
        hasOlderMessages: nextHasOlder,
      })
      setMessagesWithCache((current) => mergeMessageLists(older, current))
    } finally {
      loadingOlderMessagesRef.current = false
      setLoadingOlderMessages(false)
    }
  }

  loadOlderMessagesRef.current = () => {
    void loadOlderMessages()
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

  async function sendMessage(opts?: {
    retryTempId?: string
    retryContent?: string
    retryImageUrl?: string | null
    retryParentId?: string | null
  }) {
    if (isDemoModeActive()) {
      requestDemoSignup("comment")
      return
    }
    if (sendingMessageRef.current || sendingMessage) return
    if (!user || pageAccess !== "allowed" || !activeConversationId) return
    if (dmBlockStatus?.blockedByMe || dmBlockStatus?.blockedByOther) {
      showPopup({
        type: "error",
        message: "Direct messaging is unavailable while this user is blocked.",
      })
      return
    }

    const isRetry = Boolean(opts?.retryTempId)
    const contentText = isRetry
      ? String(opts?.retryContent ?? "")
      : input
    const selected = isRetry ? null : selectedFile
    if (!contentText.trim() && !selected && !opts?.retryImageUrl) return

    const tempId = opts?.retryTempId || createOptimisticTempId("temp")
    const parentId = isRetry
      ? opts?.retryParentId ?? null
      : replyTargetRef.current?.id ?? null
    const createdAt = new Date().toISOString()

    // Capture + clear composer immediately (keep values for failure restore).
    const prevInput = input
    const prevReply = replyTarget
    const prevFile = selectedFile
    const prevPreview = previewUrl
    const prevSelectedImage = selectedImage

    if (!isRetry) {
      setInput("")
      setReplyTarget(null)
      setSelectedFile(null)
      setSelectedImage(null)
      setPreviewUrl(null)
      if (fileRef.current) fileRef.current.value = ""
      setIsTyping(false)
    }

    const optimisticRow: any = {
      id: tempId,
      conversation_id: activeConversationId,
      sender_id: user.id,
      content: contentText || "",
      image_url: opts?.retryImageUrl ?? (prevPreview || null),
      channel: null,
      type: "text",
      created_at: createdAt,
      parent_message_id: parentId,
      client_temp_id: tempId,
      send_status: "sending",
      profiles: {
        id: user.id,
        username: null,
        name: null,
        avatar_url: null,
      },
    }

    if (isRetry) {
      setMessagesWithCache((prev) =>
        prev.map((m) =>
          String(m.id) === tempId
            ? { ...m, send_status: "sending", content: contentText }
            : m
        )
      )
    } else {
      setMessagesWithCache((prev) => [...prev, optimisticRow])
      requestScrollAfterLocalSend()
    }

    sendingMessageRef.current = true
    setSendingMessage(true)

    try {
      let imageUrl = opts?.retryImageUrl ?? null

      if (selected) {
        let uploadFile: File = selected
        if (selected.type?.startsWith("image/")) {
          uploadFile = await compressScreenshot(selected)
        }
        const fileName = `${user.id}/${Date.now()}-${uploadFile.name}`

        const { error: uploadError } = await supabase.storage
          .from("screenshots")
          .upload(fileName, uploadFile, {
            cacheControl: "31536000",
            upsert: false,
          })
        if (uploadError) {
          logSupabaseError("sendMessage image upload", uploadError, {
            bucket: "screenshots",
            path: fileName,
            userId: user.id,
          })
          setMessagesWithCache((prev) =>
            markOptimisticMessageFailed(prev, tempId)
          )
          if (!isRetry) {
            setInput(prevInput)
            setReplyTarget(prevReply)
            setSelectedFile(prevFile)
            setPreviewUrl(prevPreview)
            setSelectedImage(prevSelectedImage)
          }
          showPopup({
            type: "error",
            message: "Could not upload this image. Please try again.",
          })
          return
        }

        imageUrl = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/screenshots/${fileName}`
        setMessagesWithCache((prev) =>
          prev.map((m) =>
            String(m.id) === tempId ? { ...m, image_url: imageUrl } : m
          )
        )
      }

      const sendPayload = {
        conversation_id: activeConversationId,
        sender_id: user.id,
        content: contentText || "",
        image_url: imageUrl,
        channel: null,
        ...(parentId ? { parent_message_id: parentId } : {}),
      }
      const { data: insertedMessage, error: sendErr } = await supabase
        .from("messages")
        .insert(sendPayload)
        .select("id")
        .single()
      if (sendErr) {
        logSupabaseError("sendMessage insert", sendErr, {
          table: "messages",
          query: "insert",
          payload: sendPayload,
          userId: user.id,
        })
        setMessagesWithCache((prev) =>
          markOptimisticMessageFailed(prev, tempId)
        )
        if (!isRetry) {
          setInput((cur) => (cur.trim() ? cur : prevInput))
        }
        showPopup(dmSendFeedback(sendErr))
        return
      }

      if (insertedMessage?.id) {
        setMessagesWithCache((prev) =>
          replaceOptimisticMessage(prev, tempId, {
            ...optimisticRow,
            id: insertedMessage.id,
            image_url: imageUrl,
            send_status: "sent",
            client_temp_id: undefined,
          })
        )
        void createDirectMessagePush(supabase, String(insertedMessage.id))
      }

      const preview = previewFromMessage({
        content: contentText || null,
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
    const { data: insertedTradeMessage, error: tradeSendErr } = await supabase
      .from("messages")
      .insert(tradeSendPayload)
      .select("id")
      .single()
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

    if (insertedTradeMessage?.id) {
      void createDirectMessagePush(supabase, String(insertedTradeMessage.id))
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

    requestScrollAfterLocalSend()
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
    showPopup({ type: "success", message: "Group details saved." })
  }

  async function handleNotificationsToggle(enabled: boolean) {
    if (!user?.id || !activeConversationId || pageAccess !== "allowed") return
    const previous = notificationsEnabled
    setNotificationsEnabled(enabled)
    setNotificationsSaving(true)
    const result = await setConversationNotificationsEnabled(
      user.id,
      activeConversationId,
      enabled
    )
    setNotificationsSaving(false)
    if (!result.ok) {
      setNotificationsEnabled(previous)
      showPopup({ type: "error", message: result.message })
      return
    }
    window.dispatchEvent(new CustomEvent("tj-unread-messages-refresh"))
  }

  async function handlePinToggle(pinned: boolean) {
    if (!user?.id || !conversation?.id || pageAccess !== "allowed") return
    setPinSaving(true)
    const { error } = await supabase
      .from("conversations")
      .update({ is_pinned: pinned })
      .eq("id", conversation.id)
    setPinSaving(false)
    if (error) {
      showPopup({
        type: "error",
        message: "Could not update pin. Try again.",
      })
      return
    }
    setConversation((prev: any) =>
      prev ? { ...prev, is_pinned: pinned } : prev
    )
  }

  async function handleBlockConfirmation() {
    if (
      blockConfirmation == null ||
      !activeConversationId ||
      !user?.id ||
      conversation?.is_group
    ) {
      return
    }

    const shouldBlock = blockConfirmation
    setBlockSaving(true)
    const result = await setDmUserBlocked(activeConversationId, shouldBlock)
    setBlockSaving(false)

    if (!result.ok) {
      showPopup({
        type: "error",
        message: shouldBlock
          ? "Could not block this user. Try again."
          : "Could not unblock this user. Try again.",
      })
      return
    }

    setDmBlockStatus(result.status)
    setBlockConfirmation(null)
    setShowConversationSettings(false)
    clearMessagesInboxSessionsForUser(user.id)
    window.dispatchEvent(new CustomEvent("tj-unread-messages-refresh"))

    if (shouldBlock) {
      showPopup({ type: "success", message: "User blocked." })
      router.replace("/messages")
      return
    }

    showPopup({ type: "success", message: "User unblocked." })
  }

  async function handleLeaveConversation() {
    if (!user || pageAccess !== "allowed" || !conversation?.id) return
    setLeaveBusy(true)

    if (conversation.is_group) {
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
        logSupabaseError(
          "handleLeaveConversation system message insert",
          leaveSystemErr,
          {
            table: "messages",
            query: "insert",
            payload: leaveSystemPayload,
            userId: user.id,
            conversationId: conversation.id,
          }
        )
        setLeaveBusy(false)
        showPopup({
          type: "error",
          message: "Could not leave the group. Try again.",
        })
        return
      }
    }

    await supabase
      .from("conversation_participants")
      .delete()
      .eq("conversation_id", conversation.id)
      .eq("user_id", user.id)

    setLeaveBusy(false)
    setConfirmLeaveOpen(false)
    setShowConversationSettings(false)
    router.push("/messages")
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
  const dmMessagingBlocked =
    conversation?.is_group === false &&
    (dmBlockStatus?.blockedByMe === true ||
      dmBlockStatus?.blockedByOther === true)
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
  const groupAvatarPreviewUrl = useMemo(() => {
    if (!groupImage) return null
    return URL.createObjectURL(groupImage)
  }, [groupImage])
  useEffect(() => {
    if (!groupAvatarPreviewUrl) return
    return () => URL.revokeObjectURL(groupAvatarPreviewUrl)
  }, [groupAvatarPreviewUrl])
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
        <div
          className={`flex min-h-0 w-full flex-col items-center justify-center gap-4 px-4 text-white ${
            nativeIos
              ? "h-dvh bg-[var(--tt-surface)] pt-[var(--safe-area-top)] pb-[max(var(--safe-area-bottom),var(--keyboard-height,0px))]"
              : "h-[var(--app-viewport-height)] bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46]"
          }`}
        >
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
      <div
        data-tt-dm-thread={nativeIos ? "true" : undefined}
        className={`flex min-h-0 w-full flex-col overflow-hidden text-white ${
          nativeIos
            ? "h-dvh bg-[var(--tt-surface)]"
            : "h-[var(--app-viewport-height)] bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 pb-4 pt-2"
        }`}
      >

        <div
          className={`mx-auto flex h-full min-h-0 w-full max-w-3xl flex-col overflow-hidden ${
            nativeIos ? "" : "rounded-xl border border-white/10 bg-black/30"
          }`}
        >

          {/* HEADER */}
          {nativeIos ? (
            <div
              data-tt-dm-header
              className="relative flex shrink-0 items-center justify-between border-b border-white/10 bg-[var(--tt-surface)] px-1 pb-2.5 pt-[calc(var(--safe-area-top)+0.875rem)]"
            >
              <button
                type="button"
                aria-label="Back to messages"
                onClick={() => router.push("/messages")}
                className="-ml-0.5 flex h-11 w-11 items-center justify-center text-white"
              >
                <ChevronLeft className="h-7 w-7" strokeWidth={2.25} />
              </button>

              <div className="pointer-events-none absolute inset-x-14 top-[calc(var(--safe-area-top)+0.875rem)] bottom-2.5 flex items-center justify-center gap-2">
                {conversation?.is_group ? (
                  <img
                    src={conversation.avatar_url || "/group-default.png"}
                    alt=""
                    loading="lazy"
                    decoding="async"
                    onError={(e) => {
                      e.currentTarget.src = "/group-default.png"
                    }}
                    className="h-8 w-8 shrink-0 rounded-full object-cover"
                  />
                ) : (
                  <ProfileAvatarImg
                    src={otherUser?.avatar_url}
                    alt=""
                    className="h-8 w-8 shrink-0 rounded-full object-cover"
                  />
                )}
                <span className="truncate text-sm font-semibold leading-tight">
                  {title}
                </span>
              </div>

              <button
                type="button"
                aria-label="Conversation settings"
                title="Conversation settings"
                onClick={() => {
                  setGroupName(conversation?.name || "")
                  setShowConversationSettings(true)
                }}
                className="flex h-11 w-11 items-center justify-center"
              >
                ⚙️
              </button>
            </div>
          ) : (
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
                  type="button"
                  aria-label="Conversation settings"
                  title="Conversation settings"
                  onClick={() => {
                    setGroupName(conversation?.name || "")
                    setShowConversationSettings(true)
                  }}
                  className="p-2 md:px-3 md:py-1 md:bg-white/10 md:rounded md:hover:bg-white/20 md:text-sm"
                >
                  ⚙️
                </button>
              </div>

            </div>
          )}

          {/* MESSAGES */}
          <div
            ref={scrollRef}
            data-tt-dm-messages={nativeIos ? "true" : undefined}
            onScroll={handleMessagesScroll}
            className={`min-h-0 flex-1 overflow-y-auto overflow-x-visible px-2 py-3 md:p-4${
              nativeIos ? " bg-[var(--tt-surface)]" : ""
            }`}
          >
            {loadingOlderMessages ? (
              <p className="pb-2 text-center text-xs text-gray-500">
                Loading older messages…
              </p>
            ) : null}
            {messagesLoaded && messages.length === 0 ? (
              messagesLoadError ? (
                <EmptyState
                  title="Unable to Load Messages"
                  description="We couldn't load this conversation. Please try again."
                  className="py-10"
                  action={
                    user?.id && activeConversationId ? (
                      <button
                        type="button"
                        onClick={() => {
                          setMessagesLoadError(null)
                          setMessagesLoaded(false)
                          void loadMessages(user.id, activeConversationId)
                        }}
                        className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600"
                      >
                        Retry
                      </button>
                    ) : undefined
                  }
                />
              ) : (
                <EmptyState
                  title="No Messages Yet"
                  description="Start the conversation."
                  className="py-10"
                />
              )
            ) : null}
            <div
              className={
                messages.length > 0 && messagesLoaded && !threadScrollRevealReady
                  ? "invisible"
                  : undefined
              }
            >
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
                          } ${
                            isMe &&
                            (message.send_status === "sending" ||
                              message.send_status === "failed")
                              ? MICRO.softEnter
                              : ""
                          }`.trim()}
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
                                  <StorageImage
                                    src={message.image_url}
                                    originalSrc={message.image_url}
                                    preset="message-preview"
                                    fallbackToOriginal={false}
                                    className="max-h-64 rounded-lg"
                                    alt=""
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
                    {isMe && message.send_status === "sending" ? (
                      <SyncStatusText status="sending" />
                    ) : null}
                    {isMe && message.send_status === "failed" ? (
                      <SyncStatusText
                        status="failed"
                        onRetry={() =>
                          void sendMessage({
                            retryTempId: String(message.id),
                            retryContent: String(message.content ?? ""),
                            retryImageUrl: message.image_url ?? null,
                            retryParentId: message.parent_message_id ?? null,
                          })
                        }
                      />
                    ) : null}
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
            </div>
            {newMessagesBelowCount > 0 ? (
              <div className="sticky bottom-2 z-10 flex justify-center pb-2">
                <button
                  type="button"
                  onClick={jumpToNewestMessages}
                  className="rounded-full bg-blue-500 px-4 py-1.5 text-xs font-semibold text-white shadow-lg hover:bg-blue-600"
                >
                  {newMessagesBelowCount === 1
                    ? "New message"
                    : `${newMessagesBelowCount} new messages`}
                </button>
              </div>
            ) : null}
            <div id="chat-bottom" ref={bottomAnchorRef} />
          </div>

          {/* INPUT */}
          {previewUrl ? (
            <div className={`px-2 pb-2${nativeIos ? " bg-[var(--tt-surface)]" : ""}`}>
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

          {nativeIos ? (
            <div
              data-tt-dm-composer
              className="shrink-0 bg-[var(--tt-surface)] pb-[max(var(--safe-area-bottom),var(--keyboard-height,0px))]"
            >
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
                placeholder={
                  dmMessagingBlocked
                    ? "Direct messaging is unavailable"
                    : "Send message..."
                }
                sendDisabled={sendingMessage || dmMessagingBlocked}
                onImageChange={handleImageChange}
                imageDisabled={dmMessagingBlocked}
                fileInputRef={fileRef}
                onTradeClick={() => {
                  if (!dmMessagingBlocked) setShowTradePicker(true)
                }}
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
          ) : (
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
              placeholder={
                dmMessagingBlocked
                  ? "Direct messaging is unavailable"
                  : "Send message..."
              }
              sendDisabled={sendingMessage || dmMessagingBlocked}
              onImageChange={handleImageChange}
              imageDisabled={dmMessagingBlocked}
              fileInputRef={fileRef}
              onTradeClick={() => {
                if (!dmMessagingBlocked) setShowTradePicker(true)
              }}
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
          )}
            
        </div>

      </div>

      <ConversationSettingsModal
        open={showConversationSettings}
        onClose={() => setShowConversationSettings(false)}
        isGroup={Boolean(conversation?.is_group)}
        title={title}
        notificationsEnabled={notificationsEnabled}
        notificationsSaving={notificationsSaving}
        onNotificationsChange={(enabled) => {
          void handleNotificationsToggle(enabled)
        }}
        isPinned={conversation?.is_pinned === true}
        pinSaving={pinSaving}
        onPinChange={(pinned) => {
          void handlePinToggle(pinned)
        }}
        members={members}
        onViewSharedMedia={() => {
          setShowConversationSettings(false)
          setShowSharedMedia(true)
        }}
        blockedByMe={dmBlockStatus?.blockedByMe === true}
        blockedByOther={dmBlockStatus?.blockedByOther === true}
        blockStatusLoading={blockStatusLoading}
        onBlockUserChange={
          conversation?.is_group
            ? undefined
            : (blocked) => setBlockConfirmation(blocked)
        }
        onInviteMembers={
          conversation?.is_group
            ? () => {
                setShowConversationSettings(false)
                setShowAddMembers(true)
              }
            : undefined
        }
        onLeaveConversation={() => setConfirmLeaveOpen(true)}
        leaveLabel={
          conversation?.is_group ? "Leave Group" : "Leave Conversation"
        }
        leaveBusy={leaveBusy}
        groupName={groupName}
        onGroupNameChange={setGroupName}
        groupAvatarUrl={conversation?.avatar_url ?? null}
        groupAvatarPreviewUrl={groupAvatarPreviewUrl}
        onGroupAvatarChange={handleFileChange}
        onSaveGroupDetails={() => {
          void saveGroupSettings()
        }}
        groupDetailsSaving={savingGroupSettings}
      />

      <SharedMediaModal
        open={showSharedMedia}
        conversationId={activeConversationId}
        refreshKey={sharedMediaRefreshKey}
        onClose={() => setShowSharedMedia(false)}
      />

      <ConfirmModal
        open={blockConfirmation != null}
        onCancel={() => setBlockConfirmation(null)}
        onConfirm={handleBlockConfirmation}
        title={
          blockConfirmation
            ? `Block ${title}?`
            : `Unblock ${title}?`
        }
        description={
          blockConfirmation
            ? "Neither of you will be able to send direct messages while this block is active. This conversation will be removed from your inbox and will no longer contribute unread badges. Existing message history will not be deleted."
            : "You will both be able to continue this direct conversation. The other user will not be notified."
        }
        confirmLabel={blockConfirmation ? "Block User" : "Unblock User"}
        cancelLabel="Cancel"
        destructive={blockConfirmation === true}
        loading={blockSaving}
        loadingLabel={blockConfirmation ? "Blocking…" : "Unblocking…"}
      />

      <ConfirmModal
        open={confirmLeaveOpen}
        onCancel={() => setConfirmLeaveOpen(false)}
        onConfirm={() => {
          void handleLeaveConversation()
        }}
        title={
          conversation?.is_group ? "Leave Group?" : "Leave Conversation?"
        }
        description={
          conversation?.is_group
            ? "You will be removed from this group. You can be invited back later."
            : "This chat will be removed from your inbox. Message history is not deleted for the other person."
        }
        confirmLabel={conversation?.is_group ? "Leave Group" : "Leave"}
        cancelLabel="Cancel"
        destructive
        loading={leaveBusy}
      />

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