"use client"

import { SkeletonProfilePage } from "../../components/ui/skeletons"
import AchievementDetailModal from "../../components/AchievementDetailModal"
import FeedProfilePostDetailModal from "../../components/feed/FeedProfilePostDetailModal"
import type { ChangeEvent } from "react"
import {
  Suspense,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react"
import dynamic from "next/dynamic"
import { supabase } from "../../../lib/supabaseClient"
import { devLog, devWarn } from "@/lib/devLog"
import { deleteUserTrade } from "@/lib/deleteTrade"
import { invalidateUserStreaksCache } from "@/lib/userStreaksCache"
import { compressImage } from "@/lib/compressImage"
import { uploadToSupabaseStorageWithProgress } from "@/lib/supabaseStorageUploadWithProgress"
import {
  createMonotonicReporter,
  mapUploadBytesToPercent,
} from "@/lib/uploadProgress/reportProgress"
import { useUploadProgress } from "@/lib/uploadProgress/UploadProgressProvider"
import { useParams, useRouter, useSearchParams } from "next/navigation"
import FeedPostDetailModal from "../../components/feed/FeedPostDetailModal"
import DetailModalShell from "../../components/ui/DetailModalShell"
import ImageLightbox from "../../components/ui/ImageLightbox"
import { EMPTY_LIKE_META } from "../../components/feed/FeedPostCard"
import {
  FEED_COMMENT_INSERT_SELECT,
  FEED_POSTS_SELECT,
  postTradeOwnerUserId,
  queryFeedComments,
  reelDetailFeedItem,
} from "../../components/feed/feedPostHelpers"
import FeedRoomShareCard from "../../components/feed/FeedRoomShareCard"
import {
  buildRoomSharePostInsert,
  pendingRoomShareFromRoom,
  type PendingRoomShareDraft,
} from "@/lib/roomSharePost"
import {
  deleteFeedComment,
  deleteProfilePostComment,
  deleteAchievementPostComment,
  deleteReelComment,
  deleteTradeComment,
  filterCommentsAfterDelete,
} from "@/lib/deleteComment"
import {
  applyPinnedCommentState,
  canPinComment,
  pinCommentByKind,
  resolveCommentPinTarget,
} from "@/lib/pinComment"
import { ensureCommentNotificationsForInsert } from "@/lib/commentNotifications"
import { toggleContentLike } from "@/lib/toggleContentLike"
import {
  ensureLikeNotification,
  refreshLikeNotificationUi,
} from "@/lib/likeNotifications"
import {
  PROFILE_POST_COMMENT_INSERT_SELECT,
  insertProfilePostCommentNotifications,
  profilePostOwnerUserId,
  queryProfilePostComments,
  withInsertedProfilePostParentCommentId,
} from "@/lib/profilePostEngagement"
import {
  ACHIEVEMENT_POST_COMMENT_INSERT_SELECT,
  achievementPostOwnerUserId,
  fetchAchievementPostIdsByAchievementIds,
  fetchAchievementPostById,
  insertAchievementPostCommentNotifications,
  loadAchievementPostEngagementMaps,
  withInsertedAchievementPostParentCommentId,
} from "@/lib/achievementPostEngagement"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { supabaseMutationFeedback } from "@/lib/supabaseMutationFeedback"
import { feedbackPresets, persistentError } from "@/lib/feedbackPresets"
import ShareToConversationsModal from "../../components/ShareToConversationsModal"
import {
  type Achievement,
  fetchVisibleProfileAchievements,
} from "../../../lib/achievements"
import {
  ensureOwnAchievementsLoaded,
  getOwnAchievementsSnapshot,
} from "@/lib/userAchievementsCache"
import { loadFollowUiSnapshot } from "@/lib/followActions"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import {
  getDemoProfileMetadata,
  getDemoProfileReels,
  getDemoReelsByTradeIds,
  getDemoProfileTrades,
  getDemoProfileWallPosts,
  isDemoProfileId,
  resolveDemoProfileBySegment,
} from "@/lib/demo/demoProfile"
import FollowListModal from "@/app/components/FollowListModal"
import { invalidateFollowListCache } from "@/lib/followListPage"
import { logSupabaseError } from "@/lib/logSupabaseError"
import { ensureDmConversation } from "@/lib/dmConversation"
import { dmThreadPath } from "@/lib/messageRoutes"
import { ConfirmModal, FeedbackModal, useDeleteTradeConfirmation, useDeleteReelConfirmation, useFeedbackPopup } from "@/app/components/ui"
import { useModalScrollLock } from "@/app/components/ui/modalLayout"
import ProfileAchievementsTab from "../../components/profile/ProfileAchievementsTab"
import ProfileCalendarTab from "../../components/profile/ProfileCalendarTab"
import { PlatformProfileHeader } from "../../components/platform"
import ProfileOverviewStats from "../../components/profile/ProfileOverviewStats"
import ProfilePostsTab from "../../components/profile/ProfilePostsTab"
import ProfileReelsTab from "../../components/profile/ProfileReelsTab"
import ProfileStatisticsTab, {
  type ProfileStatisticsMode,
} from "../../components/profile/ProfileStatisticsTab"
import ProfileTabs, {
  type ProfileTab,
} from "../../components/profile/ProfileTabs"
import ProfileTradesTab from "../../components/profile/ProfileTradesTab"
import { useMobileTradeDetailSwipe } from "../../components/profile/useMobileTradeDetailSwipe"
import {
  PROFILE_TRADES_PAGE_SIZE_DESKTOP,
  PROFILE_TRADES_PAGE_SIZE_MOBILE,
  resolveProfileTradesPageSize,
} from "../../components/profile/profileTradesPagination"
import TradeCard from "../../components/profile/ProfileTradeCard"
import { useMaxMdViewport } from "@/lib/useMaxMdViewport"
import PostCard from "../../components/profile/ProfilePostCard"
import QuickTradeModal from "../../components/QuickTradeModal"
import ReelComposerModal from "../../components/profile/ReelComposerModal"
import FeedReelDetailModal from "../../components/feed/FeedReelDetailModal"
import { type ReelRow, deleteReel, fetchReelsByTradeIds, fetchUserProfileReels, replaceTradeReelVideo, isTradeAttachedReel } from "@/lib/reels"
import {
  patchFeedReelInSessionsForUser,
  removeFeedReelFromSessionsForUser,
} from "@/lib/feedSessionCache"
import {
  REEL_COMMENT_INSERT_SELECT,
  insertReelCommentNotifications,
  loadReelEngagementMaps,
  fetchReelLikeMetaByIds,
  toggleReelLike,
  withInsertedReelParentCommentId,
} from "@/lib/reelEngagement"
import StoryComposeModal from "../../components/feed/StoryComposeModal"
import ImageCropModal from "../../components/ImageCropModal"
import { useImageCropUpload } from "@/lib/useImageCropUpload"
import FeedStoryViewer from "../../components/feed/FeedStoryViewer"
import { publishStory } from "@/lib/publishStory"
import {
  getActiveStoriesForUser,
  userHasActiveStory,
} from "@/lib/activeStories"
import { useActiveStories } from "@/lib/useActiveStories"
import {
  createStoryPreviewUrl,
  prepareStoryImageFile,
  revokeStoryPreviewUrl,
} from "@/lib/storyComposeHelpers"
import { isProfileUuidSegment, profilePath } from "@/lib/profileRoutes"
import {
  aliasProfileSession,
  patchProfileSession,
  readProfileSession,
  writeProfileSession,
} from "@/lib/profileSessionCache"
import { normalizeProfileUsername } from "@/lib/profileUsername"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { notifyGettingStartedChecklistMaybeCompleted } from "@/lib/gettingStartedProgressSync"
import {
  PUBLIC_TRADE_SELECT,
  sanitizeTradeForViewer,
  sanitizeTradesForViewer,
  tradeSelectForViewer,
} from "@/lib/publicAccountPrivacy"
import { useProfileStatistics } from "./useProfileStatistics"
import { scheduleDeferredWork } from "@/lib/scheduleDeferredWork"
import NativeIosPullToRefresh from "@/app/components/NativeIosPullToRefresh"

const InputTradeForm = dynamic(() => import("../../components/InputTradeForm"), {
  ssr: false,
})

type ProfilePrefetchResource =
  | "posts"
  | "reels"
  | "analytics"
  | "achievements"
  | "room"

const PROFILE_PREFETCH_ORDER: readonly ProfilePrefetchResource[] = [
  "posts",
  "reels",
  // One existing analytics query supplies both Statistics and Calendar.
  "analytics",
  "achievements",
  "room",
]

/** Public profile columns only — never fetch billing, referral, or moderation fields here. */
const PUBLIC_PROFILE_SELECT =
  "id, username, name, bio, avatar_url, trading_style, trader_type, primary_market, started_trading, is_private, created_at" as const

const PROFILE_SUMMARY_TRADE_SELECT =
  "id, created_at, pnl, rr, mode, account_type" as const

function formatPostFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

function scrollToProfileTarget(elementId: string) {
  requestAnimationFrame(() => {
    document.getElementById(elementId)?.scrollIntoView({
      behavior: "smooth",
      block: "center",
    })
  })
}

/** Append rows without duplicate ids (pagination races, deep links). */
function mergeUniqueById<T extends { id: string | number }>(
  existing: T[],
  incoming: T[]
): T[] {
  if (!incoming.length) return existing
  const seen = new Set(existing.map((row) => String(row.id)))
  const merged = [...existing]
  for (const row of incoming) {
    const id = String(row.id)
    if (seen.has(id)) continue
    seen.add(id)
    merged.push(row)
  }
  return merged
}

function ProfilePageContent() {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const PAGE_SIZE = PROFILE_TRADES_PAGE_SIZE_DESKTOP

  const params = useParams()
  const router = useRouter()
  const searchParams = useSearchParams()
  const rawId = params.id
  const profileId =
    typeof rawId === "string"
      ? rawId.trim() || undefined
      : Array.isArray(rawId)
        ? rawId[0]?.trim() || undefined
        : undefined

  const [profile, setProfile] = useState<any>(null)
  const [allTrades, setAllTrades] = useState<any[]>([])
  const [, setVisibleTradeCount] = useState(PAGE_SIZE)
  const [tradeHasMore, setTradeHasMore] = useState(false)
  const [tradesReady, setTradesReady] = useState(false)
  const [summaryTrades, setSummaryTrades] = useState<any[]>([])
  const [summaryReady, setSummaryReady] = useState(false)
  const [analyticsTradeRows, setAnalyticsTradeRows] = useState<any[]>([])
  const [analyticsTradesReady, setAnalyticsTradesReady] = useState(false)
  const [analyticsTradesLoading, setAnalyticsTradesLoading] = useState(false)
  const [loading, setLoading] = useState(true)
  const [metaLoading, setMetaLoading] = useState(false)
  const [tradesLoading, setTradesLoading] = useState(false)
  /** Set when profile row fails to load (wrong env, RLS, missing row, or network). */
  const [lastProfileFetchError, setLastProfileFetchError] = useState<string | null>(
    null
  )
  const [followersCount, setFollowersCount] = useState(0)
  const [followingCount, setFollowingCount] = useState(0)
  const [currentUserId, setCurrentUserId] = useState<string | null>(null)
  const { profile: viewerContextProfile, user: viewerUser } = useUserProfile()
  const viewerShareProfile =
    viewerContextProfile?.referral_code != null
      ? { referral_code: viewerContextProfile.referral_code }
      : null
  const [isFollowing, setIsFollowing] = useState(false)
  const [isRequested, setIsRequested] = useState(false)
  const [followsYou, setFollowsYou] = useState(false)

  const canViewTrades = useMemo(
    () =>
      !!profile &&
      (profile.is_private !== true ||
        currentUserId === profile.id ||
        isFollowing),
    [profile, currentUserId, isFollowing]
  )
  const [messageBusy, setMessageBusy] = useState(false)
  const [room, setRoom] = useState<any | null>(null)
  const [roomReady, setRoomReady] = useState(false)
  const [showFollowers, setShowFollowers] = useState(false)
  const [showFollowing, setShowFollowing] = useState(false)
  const [wallPosts, setWallPosts] = useState<any[]>([])
  const [wallPostsReady, setWallPostsReady] = useState(false)
  const [profileReels, setProfileReels] = useState<ReelRow[]>([])
  const [profileReelsReady, setProfileReelsReady] = useState(false)
  const [tradeReelsByTradeId, setTradeReelsByTradeId] = useState<
    Record<string, ReelRow>
  >({})
  const replaceReelInputRef = useRef<HTMLInputElement>(null)
  const [replacingReelPost, setReplacingReelPost] = useState<any | null>(null)
  const [activeTab, setActiveTab] = useState<ProfileTab>("trades")
  const [profilePrefetchStep, setProfilePrefetchStep] = useState<{
    profileId: string
    resource: ProfilePrefetchResource
  } | null>(null)
  const prefetchProfileRef = useRef(profileId)
  const prefetchGenerationRef = useRef(0)
  const prefetchStartedGenerationRef = useRef(-1)
  if (prefetchProfileRef.current !== profileId) {
    prefetchProfileRef.current = profileId
    prefetchGenerationRef.current += 1
  }
  const prefetchStepForCurrentProfile =
    profilePrefetchStep?.profileId === profileId
      ? profilePrefetchStep.resource
      : null
  const prefetchingPosts = prefetchStepForCurrentProfile === "posts"
  const prefetchingReels = prefetchStepForCurrentProfile === "reels"
  const prefetchingAnalytics = prefetchStepForCurrentProfile === "analytics"
  const prefetchingAchievements =
    prefetchStepForCurrentProfile === "achievements"
  const prefetchingRoom = prefetchStepForCurrentProfile === "room"
  const postsRequested = activeTab === "posts" || prefetchingPosts
  const reelsRequested = activeTab === "reels" || prefetchingReels
  const analyticsRequested =
    activeTab === "calendar" || activeTab === "stats" || prefetchingAnalytics
  const achievementsRequested =
    activeTab === "achievements" || prefetchingAchievements
  const [showCreatePost, setShowCreatePost] = useState(false)
  const [showReelComposer, setShowReelComposer] = useState(false)
  const [showQuickTrade, setShowQuickTrade] = useState(false)
  const [editingReel, setEditingReel] = useState<ReelRow | null>(null)
  const [selectedReelDetail, setSelectedReelDetail] = useState<any | null>(null)
  const [storyComposeOpen, setStoryComposeOpen] = useState(false)
  const [pendingStoryFile, setPendingStoryFile] = useState<File | null>(null)
  const [pendingStoryPreviewUrl, setPendingStoryPreviewUrl] = useState<
    string | null
  >(null)
  const [postingStory, setPostingStory] = useState(false)
  const [postContent, setPostContent] = useState("")
  const [postImage, setPostImage] = useState<File | null>(null)
  const postImageCrop = useImageCropUpload({
    preset: "content",
    onCropped: setPostImage,
    onValidationError: (message) => showPopup({ type: "error", message }),
  })
  const [postImagePreviewUrl, setPostImagePreviewUrl] = useState<string | null>(
    null
  )
  const [pendingRoomShare, setPendingRoomShare] =
    useState<PendingRoomShareDraft | null>(null)
  const [creatingPost, setCreatingPost] = useState(false)
  const [postDetailFocusComments, setPostDetailFocusComments] = useState(false)
  const [tradeDetailFocusComments, setTradeDetailFocusComments] = useState(false)
  const [likesByPost, setLikesByPost] = useState<
    Record<string, { count: number; liked: boolean }>
  >({})
  const [commentsByPost, setCommentsByPost] = useState<Record<string, any[]>>({})
  const [commentDraft, setCommentDraft] = useState<Record<string, string>>({})
  const [commentSubmitting, setCommentSubmitting] = useState<
    Record<string, boolean>
  >({})
  const [openMenuId, setOpenMenuId] = useState<string | null>(null)
  const [editingPost, setEditingPost] = useState<any | null>(null)
  const [editContent, setEditContent] = useState("")
  const [editingTrade, setEditingTrade] = useState<any | null>(null)
  const [selectedMode, setSelectedMode] =
    useState<ProfileStatisticsMode>("all")
  const [achievements, setAchievements] = useState<Achievement[]>([])
  const [achievementsReady, setAchievementsReady] = useState(false)
  const [achievementPostIds, setAchievementPostIds] = useState<Record<string, string>>({})
  const [selectedAchievementPostDetail, setSelectedAchievementPostDetail] =
    useState<any | null>(null)
  const [selectedTradeDetail, setSelectedTradeDetail] = useState<any | null>(null)
  const [selectedPostDetail, setSelectedPostDetail] = useState<any | null>(null)
  const [screenshotLightboxUrl, setScreenshotLightboxUrl] = useState<string | null>(
    null
  )
  const [selectedAchievementDetail, setSelectedAchievementDetail] =
    useState<Achievement | null>(null)
  const [feedDeepLinkPost, setFeedDeepLinkPost] = useState<any | null>(null)
  const [sharePost, setSharePost] = useState<any | null>(null)
  const [feedDeepLinkLikeMeta, setFeedDeepLinkLikeMeta] = useState(EMPTY_LIKE_META)
  const [feedDeepLinkComments, setFeedDeepLinkComments] = useState<any[]>([])
  const [feedDeepLinkCommentSubmitting, setFeedDeepLinkCommentSubmitting] =
    useState(false)
  const feedDraftSyncRef = useRef<Record<string, string>>({})
  const feedOpenCommentsRef = useRef<Record<string, boolean>>({})
  const creatingPostRef = useRef(false)
  const uploadingPostRef = useRef(false)
  const uploadingStoryRef = useRef(false)
  const { runUpload } = useUploadProgress()
  const postingStoryRef = useRef(false)
  const STORY_SLIDE_MS = 7000
  const [profileStoryOpen, setProfileStoryOpen] = useState(false)
  const [profileStoryIndex, setProfileStoryIndex] = useState(0)
  const [profileStoriesRequested, setProfileStoriesRequested] = useState(false)
  const roomRequested = profileStoriesRequested || prefetchingRoom
  const profileStoryTriggerRef = useRef<HTMLDivElement>(null)
  const likeBusyRef = useRef<Set<string>>(new Set())
  const commentSubmittingRef = useRef<Set<string>>(new Set())
  const feedDeepLinkLikeBusyRef = useRef(false)
  const feedDeepLinkCommentSubmittingRef = useRef(false)
  const [likeBusyByPost, setLikeBusyByPost] = useState<Record<string, boolean>>({})
  const deepLinkHandledRef = useRef<string | null>(null)

  const openReelDetail = useCallback(
    (reel: ReelRow, focusComments = false) => {
      const post = reelDetailFeedItem(reel as Record<string, unknown>, profile)
      const key = String(reel.id)
      if (focusComments) {
        feedOpenCommentsRef.current[key] = true
      }
      setSelectedReelDetail(post)
    },
    [profile]
  )

  const openCreatePostModal = useCallback(() => {
    setShowCreatePost(true)
  }, [])

  const openCreateStory = useCallback(() => {
    document.getElementById("storyUploadInput")?.click()
  }, [])

  const openCreateReelModal = useCallback(() => {
    setShowReelComposer(true)
  }, [])

  const openQuickTradeModal = useCallback(() => {
    if (isDemoModeActive()) {
      requestDemoSignup("trade")
      return
    }
    setShowQuickTrade(true)
  }, [])

  const fetchProfileReels = useCallback(async (userId: string) => {
    if (isDemoModeActive() && isDemoProfileId(userId)) {
      return getDemoProfileReels(userId)
    }

    return fetchUserProfileReels(supabase, userId)
  }, [])

  /** Profile Stats equity chart: Recharts props tuned below ~sm breakpoint. */
  const [equityChartNarrow, setEquityChartNarrow] = useState(false)

  useEffect(() => {
    if (typeof window === "undefined") return
    const mq = window.matchMedia("(max-width: 639px)")
    const sync = () => setEquityChartNarrow(mq.matches)
    sync()
    mq.addEventListener("change", sync)
    return () => mq.removeEventListener("change", sync)
  }, [])

  const profileStoryUserIds = useMemo(
    () => (profile?.id ? [String(profile.id)] : []),
    [profile?.id]
  )

  const { storiesByUser: profileStoriesByUser, loadStories: loadProfileStories } =
    useActiveStories(profileStoryUserIds, !!profile?.id && profileStoriesRequested)

  useEffect(() => {
    setProfileStoriesRequested(false)
    const node = profileStoryTriggerRef.current
    if (!node || !profile?.id) return
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          setProfileStoriesRequested(true)
          observer.disconnect()
        }
      },
      { rootMargin: "100px" }
    )
    observer.observe(node)
    return () => observer.disconnect()
  }, [profile?.id])

  useEffect(() => {
    if (!profile?.id || !roomRequested || roomReady) return
    let cancelled = false

    void (async () => {
      let roomRow: (Record<string, unknown> & { owner_user_id?: string }) | null =
        null
      if (isDemoModeActive() && isDemoProfileId(String(profile.id))) {
        roomRow =
          getDemoProfileMetadata(String(profile.id), currentUserId)?.roomRow ?? null
      } else {
        const { data, error } = await supabase
          .from("rooms")
          .select("*")
          .eq("owner_user_id", profile.id)
          .maybeSingle()
        if (error) console.error(error)
        roomRow = data ?? null
      }
      if (cancelled) return
      const resolved =
        roomRow && roomRow.owner_user_id === profile.id ? roomRow : null
      setRoom(resolved)
      setRoomReady(true)
      patchProfileSession(profileId, { room: resolved, roomReady: true })
    })()

    return () => {
      cancelled = true
    }
  }, [
    currentUserId,
    profile?.id,
    profileId,
    roomRequested,
    roomReady,
  ])

  const profileHasActiveStory = userHasActiveStory(
    profileStoriesByUser,
    profile?.id
  )

  const profileStorySlides = useMemo(
    () => getActiveStoriesForUser(profileStoriesByUser, profile?.id),
    [profileStoriesByUser, profile?.id]
  )

  const profileCurrentStory = profileStorySlides[profileStoryIndex] ?? null

  const profileStoryBarUsers = useMemo(
    () =>
      profile
        ? [
            {
              id: String(profile.id),
              username: profile.username,
              avatar_url: profile.avatar_url,
            },
          ]
        : [],
    [profile]
  )

  useEffect(() => {
    if (!profileStoryOpen) return
    if (profileStorySlides.length === 0) {
      setProfileStoryOpen(false)
      setProfileStoryIndex(0)
      return
    }
    if (profileStoryIndex >= profileStorySlides.length) {
      setProfileStoryIndex(Math.max(0, profileStorySlides.length - 1))
    }
  }, [profileStoryOpen, profileStoryIndex, profileStorySlides.length])

  useEffect(() => {
    if (!profileStoryOpen || profileStorySlides.length === 0) return
    if (profileStoryIndex >= profileStorySlides.length - 1) return

    const timer = window.setTimeout(() => {
      setProfileStoryIndex((prev) => prev + 1)
    }, STORY_SLIDE_MS)

    return () => window.clearTimeout(timer)
  }, [profileStoryOpen, profileStoryIndex, profileStorySlides.length])

  useEffect(() => {
    if (!postImage) {
      setPostImagePreviewUrl(null)
      return
    }

    const url = createStoryPreviewUrl(postImage)
    setPostImagePreviewUrl(url)

    return () => {
      revokeStoryPreviewUrl(url)
    }
  }, [postImage])

  const closeStoryCompose = useCallback(() => {
    revokeStoryPreviewUrl(pendingStoryPreviewUrl)
    setPendingStoryPreviewUrl(null)
    setPendingStoryFile(null)
    setStoryComposeOpen(false)
  }, [pendingStoryPreviewUrl])

  useEffect(() => {
    return () => {
      revokeStoryPreviewUrl(pendingStoryPreviewUrl)
    }
  }, [pendingStoryPreviewUrl])

  const setStoryDraft = useCallback(
    async (file: File) => {
      const prepared = await prepareStoryImageFile(file)
      revokeStoryPreviewUrl(pendingStoryPreviewUrl)
      setPendingStoryFile(prepared)
      setPendingStoryPreviewUrl(createStoryPreviewUrl(prepared))
      setStoryComposeOpen(true)
    },
    [pendingStoryPreviewUrl]
  )

  const handleStoryFileSelect = useCallback(
    async (e: ChangeEvent<HTMLInputElement>) => {
      const input = e.target
      const file = input.files?.[0]
      input.value = ""
      if (!file || !currentUserId) return
      await setStoryDraft(file)
    },
    [currentUserId, setStoryDraft]
  )

  const handlePostStory = useCallback(async () => {
    if (
      !pendingStoryFile ||
      !currentUserId ||
      postingStoryRef.current ||
      postingStory ||
      uploadingStoryRef.current
    ) {
      return
    }

    const storyFile = pendingStoryFile
    uploadingStoryRef.current = true

    try {
      await runUpload({
        title: "Uploading Story",
        onDismissCompose: closeStoryCompose,
        execute: async (report) => {
          postingStoryRef.current = true
          setPostingStory(true)

          const result = await publishStory(supabase, currentUserId, storyFile, {
            onProgress: report,
          })

          if (!result.ok) {
            throw new Error(result.message)
          }

          showPopup({ type: "success", message: "Story uploaded!" })
          await loadProfileStories()
        },
      })
    } catch {
      // Overlay handles retry/cancel.
    } finally {
      postingStoryRef.current = false
      setPostingStory(false)
      uploadingStoryRef.current = false
    }
  }, [
    pendingStoryFile,
    currentUserId,
    postingStory,
    showPopup,
    closeStoryCompose,
    loadProfileStories,
    runUpload,
  ])

  const fetchTradesForProfile = useCallback(
    async (
      forProfileId: string,
      offset: number,
      pageSize: number = resolveProfileTradesPageSize()
    ) => {
      const isOwner =
        currentUserId != null && String(currentUserId) === String(forProfileId)

      if (isDemoModeActive() && isDemoProfileId(forProfileId)) {
        const rows = getDemoProfileTrades(forProfileId, currentUserId)
        return {
          rows: rows.slice(offset, offset + pageSize),
          hasMore: rows.length > offset + pageSize,
        }
      }

      // Inclusive range end fetches pageSize + 1 rows to detect hasMore.
      const { data, error } = await supabase
        .from("trades")
        .select(tradeSelectForViewer(isOwner))
        .eq("user_id", forProfileId)
        .eq("is_public", true)
        .order("created_at", { ascending: false })
        .range(offset, offset + pageSize)

      if (error) {
        console.error("profile trades page fetch:", error)
        return { rows: [], hasMore: false }
      }

      const rows = sanitizeTradesForViewer(data || [], { isOwner })
      return {
        rows: rows.slice(0, pageSize),
        hasMore: rows.length > pageSize,
      }
    },
    [currentUserId]
  )

  const fetchAllTradesForAnalytics = useCallback(
    async (forProfileId: string) => {
      const isOwner =
        currentUserId != null && String(currentUserId) === String(forProfileId)
      if (isDemoModeActive() && isDemoProfileId(forProfileId)) {
        return getDemoProfileTrades(forProfileId, currentUserId)
      }
      const { data, error } = await supabase
        .from("trades")
        .select(tradeSelectForViewer(isOwner))
        .eq("user_id", forProfileId)
        .eq("is_public", true)
        .order("created_at", { ascending: false })
      if (error) {
        console.error("profile analytics trades fetch:", error)
        return []
      }
      return sanitizeTradesForViewer(data || [], { isOwner })
    },
    [currentUserId]
  )

  const fetchSummaryTrades = useCallback(async (forProfileId: string) => {
    if (isDemoModeActive() && isDemoProfileId(forProfileId)) {
      return getDemoProfileTrades(forProfileId, currentUserId)
    }
    const { data, error } = await supabase
      .from("trades")
      .select(PROFILE_SUMMARY_TRADE_SELECT)
      .eq("user_id", forProfileId)
      .eq("is_public", true)
      .order("created_at", { ascending: false })
    if (error) {
      console.error("profile summary fetch:", error)
      return []
    }
    return data || []
  }, [currentUserId])

  const refreshProfileMedia = useCallback(async () => {
    if (!profile?.id) return

    const userId = String(profile.id)
    const [page, summary] = await Promise.all([
      fetchTradesForProfile(userId, 0),
      fetchSummaryTrades(userId),
    ])
    setAllTrades(page.rows)
    setVisibleTradeCount(page.rows.length)
    setTradeHasMore(page.hasMore)
    setTradesReady(true)
    setSummaryTrades(summary)
    setSummaryReady(true)
    patchProfileSession(profileId, {
      allTrades: page.rows,
      visibleTradeCount: page.rows.length,
      tradeHasMore: page.hasMore,
      tradesReady: true,
      summaryTrades: summary,
      summaryReady: true,
    })
  }, [fetchSummaryTrades, fetchTradesForProfile, profile?.id, profileId])

  const loadMoreTrades = useCallback(async () => {
    if (!profile?.id || tradesLoading || !tradeHasMore) return
    setTradesLoading(true)
    try {
      const page = await fetchTradesForProfile(String(profile.id), allTrades.length)
      const merged = mergeUniqueById(allTrades, page.rows)
      setAllTrades(merged)
      setVisibleTradeCount(merged.length)
      setTradeHasMore(page.hasMore)
      patchProfileSession(profileId, {
        allTrades: merged,
        visibleTradeCount: merged.length,
        tradeHasMore: page.hasMore,
        tradesReady: true,
      })
    } finally {
      setTradesLoading(false)
    }
  }, [
    allTrades,
    fetchTradesForProfile,
    profile?.id,
    profileId,
    tradeHasMore,
    tradesLoading,
  ])

  const publicTradesByDate = useMemo(
    () =>
      allTrades
        .filter((trade) => trade.is_public === true)
        .sort(
          (a, b) =>
            new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
        ),
    [allTrades]
  )

  const trades = useMemo(
    () => publicTradesByDate,
    [publicTradesByDate]
  )

  const hasMore = tradeHasMore

  useEffect(() => {
    if (!profileId) {
      setProfile(null)
      setRoom(null)
      setRoomReady(false)
      setAllTrades([])
      setVisibleTradeCount(PAGE_SIZE)
      setTradeHasMore(false)
      setTradesReady(false)
      setSummaryTrades([])
      setSummaryReady(false)
      setAnalyticsTradeRows([])
      setAnalyticsTradesReady(false)
      setLoading(false)
      return
    }

    // Close follow modals when navigating to another profile.
    setShowFollowers(false)
    setShowFollowing(false)

    const cached = readProfileSession(profileId)
    if (cached) {
      setProfile(cached.profile)
      setRoom(cached.room)
      setRoomReady(cached.roomReady ?? cached.room != null)
      setFollowersCount(cached.followersCount)
      setFollowingCount(cached.followingCount)
      setIsFollowing(cached.isFollowing)
      setIsRequested(cached.isRequested)
      setFollowsYou(cached.followsYou)
      setAllTrades(cached.allTrades)
      setWallPosts(cached.wallPosts)
      setVisibleTradeCount(cached.visibleTradeCount)
      setTradeHasMore(cached.tradeHasMore ?? false)
      setTradesReady(cached.tradesReady ?? cached.allTrades.length > 0)
      setWallPostsReady(cached.wallPostsReady ?? cached.wallPosts.length > 0)
      setProfileReels((cached.profileReels ?? []) as ReelRow[])
      setProfileReelsReady(cached.profileReelsReady ?? false)
      setAchievements((cached.achievements ?? []) as Achievement[])
      setAchievementsReady(cached.achievementsReady ?? false)
      setAnalyticsTradeRows((cached.analyticsTrades ?? []) as any[])
      setAnalyticsTradesReady(cached.analyticsTradesReady ?? false)
      setSummaryTrades((cached.summaryTrades ?? []) as any[])
      setSummaryReady(cached.summaryReady ?? false)
      if (cached.activeTab) {
        setActiveTab(cached.activeTab as typeof activeTab)
      }
      if (cached.selectedMode) {
        setSelectedMode(cached.selectedMode as ProfileStatisticsMode)
      }
      setLoading(false)
      setMetaLoading(false)
      setTradesLoading(false)
      deepLinkHandledRef.current = null
      if (cached.scrollY > 0) {
        requestAnimationFrame(() => window.scrollTo(0, cached.scrollY))
      }
      void refreshProfileInBackground(profileId)
      return
    }

    devLog("ProfileId from URL:", profileId)

    setProfile(null)
    setAllTrades([])
    setVisibleTradeCount(PAGE_SIZE)
    setTradeHasMore(false)
    setTradesReady(false)
    setWallPosts([])
    setWallPostsReady(false)
    setProfileReels([])
    setProfileReelsReady(false)
    setAchievements([])
    setAchievementsReady(false)
    setAnalyticsTradeRows([])
    setAnalyticsTradesReady(false)
    setSummaryTrades([])
    setSummaryReady(false)
    setRoom(null)
    setRoomReady(false)
    setLoading(true)

    fetchProfile(profileId)
    deepLinkHandledRef.current = null
  }, [profileId])

  useEffect(() => {
    if (!profile?.id || !canViewTrades || activeTab !== "trades" || tradesReady) {
      // Only clear when a resolved profile is genuinely not viewable; while the
      // profile is still restoring (null), clearing here would wipe cached trades.
      if (profile?.id && !canViewTrades) {
        setAllTrades([])
        setTradeHasMore(false)
        setTradesReady(false)
        setTradesLoading(false)
      }
      return
    }

    let cancelled = false
    setTradesLoading(true)

    void (async () => {
      const page = await fetchTradesForProfile(profile.id, 0)
      if (!cancelled) {
        setAllTrades(page.rows)
        setVisibleTradeCount(page.rows.length)
        setTradeHasMore(page.hasMore)
        setTradesReady(true)
        setTradesLoading(false)
        patchProfileSession(profileId, {
          allTrades: page.rows,
          visibleTradeCount: page.rows.length,
          tradeHasMore: page.hasMore,
          tradesReady: true,
        })
      }
    })()

    return () => {
      cancelled = true
    }
  }, [
    activeTab,
    canViewTrades,
    fetchTradesForProfile,
    profile?.id,
    profileId,
    tradesReady,
  ])

  useEffect(() => {
    if (!profile?.id || !canViewTrades || summaryReady) return
    let cancelled = false
    void fetchSummaryTrades(String(profile.id)).then((rows) => {
      if (cancelled) return
      setSummaryTrades(rows)
      setSummaryReady(true)
      patchProfileSession(profileId, { summaryTrades: rows, summaryReady: true })
    })
    return () => {
      cancelled = true
    }
  }, [canViewTrades, fetchSummaryTrades, profile?.id, profileId, summaryReady])

  // Start secondary work only after the critical profile is interactive:
  // header resolved, default Trades usable, and overview summary available.
  // Each completion schedules the next resource in a separate idle slice, so
  // tab warming never creates a request burst or competes with first paint.
  useEffect(() => {
    if (!profileId || loading || !profile?.id) return
    if (canViewTrades && (!tradesReady || !summaryReady)) return

    const generation = prefetchGenerationRef.current
    if (prefetchStartedGenerationRef.current === generation) return
    prefetchStartedGenerationRef.current = generation

    scheduleDeferredWork(() => {
      if (
        prefetchGenerationRef.current !== generation ||
        prefetchProfileRef.current !== profileId
      ) {
        return
      }
      setProfilePrefetchStep({
        profileId,
        resource: PROFILE_PREFETCH_ORDER[0],
      })
    }, 1000)
  }, [
    canViewTrades,
    loading,
    profile?.id,
    profileId,
    summaryReady,
    tradesReady,
  ])

  useEffect(() => {
    const step = profilePrefetchStep
    if (!step || step.profileId !== profileId) return

    const ready =
      step.resource === "posts"
        ? wallPostsReady
        : step.resource === "reels"
          ? profileReelsReady
          : step.resource === "analytics"
            ? analyticsTradesReady
            : step.resource === "achievements"
              ? achievementsReady
              : roomReady
    if (!ready) return

    const currentIndex = PROFILE_PREFETCH_ORDER.indexOf(step.resource)
    const nextResource = PROFILE_PREFETCH_ORDER[currentIndex + 1]
    const generation = prefetchGenerationRef.current
    scheduleDeferredWork(() => {
      if (
        prefetchGenerationRef.current !== generation ||
        prefetchProfileRef.current !== step.profileId
      ) {
        return
      }
      setProfilePrefetchStep(
        nextResource
          ? { profileId: step.profileId, resource: nextResource }
          : null
      )
    }, 750)
  }, [
    achievementsReady,
    analyticsTradesReady,
    profileId,
    profilePrefetchStep,
    profileReelsReady,
    roomReady,
    wallPostsReady,
  ])

  useEffect(() => {
    if (
      !profile?.id ||
      !canViewTrades ||
      !analyticsRequested ||
      analyticsTradesReady
    ) {
      return
    }
    let cancelled = false
    setAnalyticsTradesLoading(true)
    void fetchAllTradesForAnalytics(String(profile.id)).then((rows) => {
      if (cancelled) return
      setAnalyticsTradeRows(rows)
      setAnalyticsTradesReady(true)
      setAnalyticsTradesLoading(false)
      patchProfileSession(profileId, {
        analyticsTrades: rows,
        analyticsTradesReady: true,
      })
    })
    return () => {
      cancelled = true
    }
  }, [
    analyticsRequested,
    analyticsTradesReady,
    canViewTrades,
    fetchAllTradesForAnalytics,
    profile?.id,
    profileId,
  ])

  useEffect(() => {
    // Guard on profile?.id: on remount the profile is briefly null before the
    // session cache restore commits, and clearing then would discard cached
    // trades while tradesReady stays true (blocking any refetch).
    if (profile?.id && !canViewTrades) {
      setAllTrades([])
      setVisibleTradeCount(PAGE_SIZE)
      setTradesLoading(false)
    }
  }, [profile?.id, canViewTrades])

  useEffect(() => {
    if (activeTab !== "trades" || !allTrades.length) {
      setTradeReelsByTradeId({})
      return
    }

    let cancelled = false
    const tradeIds = allTrades
      .map((trade) => String(trade.id))
      .filter((id) => id.trim() !== "")

    if (
      isDemoModeActive() &&
      profile?.id &&
      isDemoProfileId(String(profile.id))
    ) {
      const map = getDemoReelsByTradeIds(String(profile.id), tradeIds)
      const record: Record<string, ReelRow> = {}
      map.forEach((reel, tradeId) => {
        record[tradeId] = reel
      })
      setTradeReelsByTradeId(record)
      return () => {
        cancelled = true
      }
    }

    void fetchReelsByTradeIds(supabase, tradeIds).then((map) => {
      if (cancelled) return
      const record: Record<string, ReelRow> = {}
      map.forEach((reel, tradeId) => {
        record[tradeId] = reel
      })
      setTradeReelsByTradeId(record)
    })

    return () => {
      cancelled = true
    }
  }, [activeTab, allTrades, profile?.id])

  useEffect(() => {
    // Profile is null during the first commit on remount (before the session
    // cache restore applies); clearing here would wipe cached posts.
    if (!profile?.id) return
    if (!postsRequested || wallPostsReady) return

    let cancelled = false
    setWallPostsReady(false)

    async function fetchWallPosts() {
      if (isDemoModeActive() && isDemoProfileId(String(profile.id))) {
        const data = getDemoProfileWallPosts(String(profile.id))
        if (cancelled) return
        setWallPosts(data)
        setWallPostsReady(true)
        patchProfileSession(profileId, { wallPosts: data, wallPostsReady: true })
        return
      }

      const { data, error } = await supabase
        .from("profile_posts")
        .select("*")
        .eq("user_id", profile.id)
        .order("created_at", { ascending: false })

      if (cancelled) return
      if (error) {
        console.error("profile_posts fetch:", error)
        setWallPosts([])
        setWallPostsReady(true)
        return
      }
      setWallPosts(data || [])
      setWallPostsReady(true)
      patchProfileSession(profileId, {
        wallPosts: data || [],
        wallPostsReady: true,
      })
    }

    void fetchWallPosts()

    return () => {
      cancelled = true
    }
  }, [postsRequested, profile?.id, profileId, wallPostsReady])

  useEffect(() => {
    // See posts effect: don't clear cached reels while profile is restoring.
    if (!profile?.id) return
    if (!reelsRequested || profileReelsReady) return

    let cancelled = false
    setProfileReelsReady(false)

    async function loadReels() {
      const data = await fetchProfileReels(String(profile.id))
      if (cancelled) return
      setProfileReels(data)
      if (data.length > 0) {
        const reelIds = data.map((row) => String(row.id))
        const { likesMap, commentsMap } = await loadReelEngagementMaps(
          supabase,
          reelIds,
          currentUserId
        )
        if (!cancelled) {
          setLikesByPost((prev) => ({ ...prev, ...likesMap }))
          setCommentsByPost((prev) => ({ ...prev, ...commentsMap }))
        }
      }
      setProfileReelsReady(true)
      patchProfileSession(profileId, {
        profileReels: data,
        profileReelsReady: true,
      })
    }

    void loadReels()

    return () => {
      cancelled = true
    }
  }, [
    currentUserId,
    fetchProfileReels,
    profile?.id,
    profileId,
    profileReelsReady,
    reelsRequested,
  ])

  const profileReelIdsKey = useMemo(
    () => profileReels.map((row) => String(row.id)).sort().join(","),
    [profileReels]
  )

  useEffect(() => {
    if (activeTab !== "reels" || !profile?.id || !profileReelIdsKey) return
    if (isDemoModeActive()) return

    const reelIds = profileReelIdsKey.split(",").filter(Boolean)
    const channel = supabase.channel(`profile-reel-likes-${profile.id}`)

    const refreshReelLike = (reelId: string) => {
      void (async () => {
        const metaById = await fetchReelLikeMetaByIds(
          supabase,
          [reelId],
          currentUserId
        )
        const next = metaById[reelId]
        if (!next) return
        setLikesByPost((prev) => ({ ...prev, [reelId]: next }))
      })()
    }

    for (const reelId of reelIds) {
      channel.on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "reel_likes",
          filter: `reel_id=eq.${reelId}`,
        },
        () => {
          refreshReelLike(reelId)
        }
      )
    }

    channel.subscribe()

    return () => {
      void supabase.removeChannel(channel)
    }
  }, [activeTab, profile?.id, profileReelIdsKey, currentUserId])

  useEffect(() => {
    // See posts effect: don't clear cached achievements while profile is restoring.
    if (!profile?.id) return
    if (!achievementsRequested || achievementsReady) return
    let cancelled = false
    async function fetchProfileAchievements() {
      const isOwner =
        currentUserId != null && String(currentUserId) === String(profile.id)
      if (isOwner) {
        const cached = getOwnAchievementsSnapshot(profile.id)
        if (cached) {
          if (!cancelled) {
            setAchievements(cached)
            setAchievementsReady(true)
            patchProfileSession(profileId, {
              achievements: cached,
              achievementsReady: true,
            })
          }
          return
        }
        const data = await ensureOwnAchievementsLoaded(supabase, profile.id)
        if (cancelled) return
        setAchievements(data)
        setAchievementsReady(true)
        patchProfileSession(profileId, {
          achievements: data,
          achievementsReady: true,
        })
        return
      }
      const query = await fetchVisibleProfileAchievements(profile.id)
      const { data, error } = query
      if (cancelled) return
      if (error) {
        console.error("profile achievements fetch:", error)
        setAchievements([])
        setAchievementsReady(true)
        return
      }
      const rows = (data || []) as Achievement[]
      setAchievements(rows)
      setAchievementsReady(true)
      patchProfileSession(profileId, {
        achievements: rows,
        achievementsReady: true,
      })
    }
    void fetchProfileAchievements()
    return () => {
      cancelled = true
    }
  }, [
    achievementsReady,
    achievementsRequested,
    currentUserId,
    profile?.id,
    profileId,
  ])

  useEffect(() => {
    if (activeTab !== "achievements" || !achievements.length) {
      setAchievementPostIds({})
      return
    }

    let cancelled = false
    async function loadAchievementEngagement() {
      const map = await fetchAchievementPostIdsByAchievementIds(
        supabase,
        achievements.map((a) => String(a.id))
      )
      if (cancelled) return
      setAchievementPostIds(map)

      const postIds = Object.values(map)
      if (postIds.length === 0) return

      const { likesMap, commentsMap } = await loadAchievementPostEngagementMaps(
        supabase,
        postIds,
        currentUserId
      )
      if (cancelled) return
      setLikesByPost((prev) => ({ ...prev, ...likesMap }))
      setCommentsByPost((prev) => ({ ...prev, ...commentsMap }))
    }

    void loadAchievementEngagement()
    return () => {
      cancelled = true
    }
  }, [achievements, activeTab, currentUserId])

  useEffect(() => {
    if (!profileId || loading) return
    const onScroll = () => {
      const cached = readProfileSession(profileId)
      if (!cached) return
      patchProfileSession(profileId, { scrollY: window.scrollY })
    }
    window.addEventListener("scroll", onScroll, { passive: true })
    return () => window.removeEventListener("scroll", onScroll)
  }, [profileId, loading])

  useEffect(() => {
    if (!profileId || loading) return
    patchProfileSession(profileId, { activeTab, selectedMode })
  }, [activeTab, loading, profileId, selectedMode])

  const profileOverlayOpen =
    showCreatePost ||
    showReelComposer ||
    showQuickTrade ||
    editingReel ||
    selectedReelDetail ||
    editingPost ||
    selectedAchievementDetail ||
    selectedTradeDetail ||
    selectedPostDetail ||
    feedDeepLinkPost ||
    sharePost
  useModalScrollLock(profileOverlayOpen)

  useEffect(() => {
    if (
      !showCreatePost &&
      !showReelComposer &&
      !showQuickTrade &&
      !editingReel &&
      !selectedReelDetail &&
      !editingPost &&
      !selectedAchievementDetail &&
      !selectedTradeDetail &&
      !selectedPostDetail &&
      !feedDeepLinkPost &&
      !sharePost
    )
      return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") {
        setShowCreatePost(false)
        setPendingRoomShare(null)
        setEditingPost(null)
        setShowReelComposer(false)
        setEditingReel(null)
        setSelectedAchievementDetail(null)
        setSelectedTradeDetail(null)
        setSelectedPostDetail(null)
        setSelectedReelDetail(null)
        setFeedDeepLinkPost(null)
        setSharePost(null)
      }
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [
    showCreatePost,
    editingPost,
    selectedAchievementDetail,
    selectedTradeDetail,
    selectedPostDetail,
    feedDeepLinkPost,
    sharePost,
  ])

  useEffect(() => {
    if (viewerUser?.id) {
      setCurrentUserId(viewerUser.id)
    }
  }, [viewerUser?.id])

  const applyProfileMetadata = useCallback(
    async (
      segment: string,
      prof: { id: string },
      uid: string | null
    ) => {
      const followPromise =
        uid && uid !== prof.id
          ? loadFollowUiSnapshot(supabase, uid, prof.id)
          : Promise.resolve(null)

      const [snapshot, followersRes, followingRes] = await Promise.all([
        followPromise,
        supabase
          .from("followers")
          .select("*", { count: "exact", head: true })
          .eq("following_id", prof.id),
        supabase
          .from("followers")
          .select("*", { count: "exact", head: true })
          .eq("follower_id", prof.id),
      ])

      let following = false
      let requested = false
      let profileFollowsYou = false
      if (snapshot) {
        following = snapshot.state === "following"
        requested = snapshot.state === "requested"
        profileFollowsYou = snapshot.followsYou
      }

      setIsFollowing(following)
      setIsRequested(requested)
      setFollowsYou(profileFollowsYou)

      const followersN = followersRes.count ?? 0
      const followingN = followingRes.count ?? 0
      setFollowersCount(followersN)
      setFollowingCount(followingN)

      patchProfileSession(segment, {
        followersCount: followersN,
        followingCount: followingN,
        isFollowing: following,
        isRequested: requested,
        followsYou: profileFollowsYou,
      })

      return { following, requested, profileFollowsYou, followersN, followingN }
    },
    []
  )

  async function refreshProfileInBackground(urlSegment: string) {
    const segment = urlSegment.trim()
    const lookupByUuid = isProfileUuidSegment(segment)

    let profileQuery = supabase.from("profiles").select(PUBLIC_PROFILE_SELECT)
    if (lookupByUuid) {
      profileQuery = profileQuery.eq("id", segment)
    } else {
      profileQuery = profileQuery.eq(
        "username",
        normalizeProfileUsername(segment)
      )
    }

    const uid = viewerUser?.id ?? null

    setMetaLoading(true)
    try {
      const { data: prof, error } = await profileQuery.maybeSingle()
      if (error || !prof) return

      setProfile(prof)
      patchProfileSession(segment, { profile: prof })

      await applyProfileMetadata(segment, prof, uid)

      if (lookupByUuid && prof.username) {
        const target = profilePath(prof)
        aliasProfileSession(segment, String(prof.username).trim())
        const qs = searchParams.toString()
        router.replace(qs ? `${target}?${qs}` : target, { scroll: false })
      }
    } finally {
      setMetaLoading(false)
    }
  }

  async function fetchProfile(urlSegment: string) {
    const segment = urlSegment.trim()
    const lookupByUuid = isProfileUuidSegment(segment)
    const devProfileDebug =
      process.env.NODE_ENV === "development" ||
      process.env.NEXT_PUBLIC_PROFILE_FETCH_DEBUG === "1"

    if (devProfileDebug) {
      devLog("SUPABASE URL:", process.env.NEXT_PUBLIC_SUPABASE_URL)
      devLog("FETCHING PROFILE SEGMENT:", segment, { lookupByUuid })
    }

    setLastProfileFetchError(null)

    const uid = viewerUser?.id ?? null
    setCurrentUserId(uid)

    if (isDemoModeActive()) {
      const demoProf = resolveDemoProfileBySegment(segment)
      if (!demoProf) {
        setProfile(null)
        setRoom(null)
        setAllTrades([])
        setVisibleTradeCount(PAGE_SIZE)
        setFollowersCount(0)
        setFollowingCount(0)
        setIsFollowing(false)
        setIsRequested(false)
        setFollowsYou(false)
        setLoading(false)
        setMetaLoading(false)
        setTradesLoading(false)
        return
      }

      setProfile(demoProf)
      setLoading(false)

      const meta = getDemoProfileMetadata(demoProf.id, uid)
      if (meta) {
        setIsFollowing(meta.following)
        setIsRequested(meta.requested)
        setFollowsYou(meta.profileFollowsYou)
        setFollowersCount(meta.followersN)
        setFollowingCount(meta.followingN)
      }

      writeProfileSession(segment, {
        profile: demoProf,
        room: null,
        roomReady: false,
        followersCount: meta?.followersN ?? 0,
        followingCount: meta?.followingN ?? 0,
        isFollowing: meta?.following ?? false,
        isRequested: meta?.requested ?? false,
        followsYou: meta?.profileFollowsYou ?? false,
        allTrades: [],
        wallPosts: [],
        visibleTradeCount: PAGE_SIZE,
        scrollY: 0,
      })
      setMetaLoading(false)
      return
    }

    if (devProfileDebug) {
      void supabase
        .from("profiles")
        .select(PUBLIC_PROFILE_SELECT)
        .limit(50)
        .then((listProbe) => {
          devLog("PROFILE DEBUG (list up to 50 rows):", {
            rowCount: listProbe.data?.length ?? 0,
            error: listProbe.error,
            sampleIds: listProbe.data?.slice(0, 5).map((r: { id: string }) => r.id),
          })
        })
    }

    let profileQuery = supabase.from("profiles").select(PUBLIC_PROFILE_SELECT)
    if (lookupByUuid) {
      profileQuery = profileQuery.eq("id", segment)
    } else {
      profileQuery = profileQuery.eq(
        "username",
        normalizeProfileUsername(segment)
      )
    }

    const { data: prof, error } = await profileQuery.maybeSingle()

    if (devProfileDebug) {
      devLog("PROFILE DATA:", prof)
      devLog("ERROR:", error)
    }

    if (error) {
      setLastProfileFetchError(
        [error.message, (error as { code?: string }).code]
          .filter(Boolean)
          .join(" ")
      )
    } else if (!prof) {
      setLastProfileFetchError(
        "No row returned (missing id in this DB, or RLS hid the row)."
      )
    }

    if (!prof || error) {
      setProfile(null)
      setRoom(null)
      setAllTrades([])
      setVisibleTradeCount(PAGE_SIZE)
      setFollowersCount(0)
      setFollowingCount(0)
      setIsFollowing(false)
      setIsRequested(false)
      setFollowsYou(false)
      setLoading(false)
      setMetaLoading(false)
      setTradesLoading(false)
      return
    }

    setProfile(prof)
    setLoading(false)

    writeProfileSession(segment, {
      profile: prof,
      room: null,
      followersCount: 0,
      followingCount: 0,
      isFollowing: false,
      isRequested: false,
      followsYou: false,
      allTrades: [],
      wallPosts: [],
      visibleTradeCount: PAGE_SIZE,
      scrollY: 0,
    })

    setMetaLoading(true)
    try {
      const meta = await applyProfileMetadata(segment, prof, uid)
      writeProfileSession(segment, {
        profile: prof,
        room: null,
        roomReady: false,
        followersCount: meta.followersN,
        followingCount: meta.followingN,
        isFollowing: meta.following,
        isRequested: meta.requested,
        followsYou: meta.profileFollowsYou,
        allTrades: [],
        wallPosts: [],
        visibleTradeCount: PAGE_SIZE,
        scrollY: 0,
      })

      if (lookupByUuid && prof.username) {
        const target = profilePath(prof)
        aliasProfileSession(segment, String(prof.username).trim())
        const qs = searchParams.toString()
        router.replace(qs ? `${target}?${qs}` : target, { scroll: false })
      }
    } finally {
      setMetaLoading(false)
    }
  }

  async function handleMessage() {
    if (!currentUserId || !profile || currentUserId === profile.id) return

    if (isDemoModeActive()) {
      router.push(dmThreadPath(profile))
      return
    }

    setMessageBusy(true)
    try {
      const result = await ensureDmConversation(
        supabase,
        currentUserId,
        profile.id,
        { skipGroupFilter: true }
      )

      if (!result.ok) {
        if (result.phase === "conversation") {
          logSupabaseError("handleMessage conversations insert", result.error, {
            table: "conversations",
            query: "insert",
            payload: { id: result.conversationId, is_group: false },
            userId: currentUserId,
            otherUserId: profile.id,
          })
        } else {
          logSupabaseError(
            "handleMessage conversation_participants insert",
            result.error,
            {
              table: "conversation_participants",
              query: "insert",
              payload: [
                { conversation_id: result.conversationId, user_id: currentUserId },
                { conversation_id: result.conversationId, user_id: profile.id },
              ],
              userId: currentUserId,
              conversationId: result.conversationId,
              otherUserId: profile.id,
            }
          )
        }
        return
      }

      router.push(dmThreadPath(profile))
    } finally {
      setMessageBusy(false)
    }
  }

  function closeFollowModals() {
    setShowFollowers(false)
    setShowFollowing(false)
  }

  function openFollowersModal() {
    if (!profile) return
    setShowFollowing(false)
    setShowFollowers(true)
  }

  function openFollowingModal() {
    if (!profile) return
    setShowFollowers(false)
    setShowFollowing(true)
  }

  async function handleCreatePost() {
    if (!currentUserId || !profile || currentUserId !== profile.id) return
    if (isDemoModeActive()) {
      requestDemoSignup("comment")
      return
    }
    if (creatingPostRef.current || creatingPost || uploadingPostRef.current) {
      return
    }

    const text = postContent.trim()
    if (!text && !postImage && !pendingRoomShare) {
      showPopup({ type: "warning", message: "Add some text, an image, or a room share." })
      return
    }

    void import("@/lib/nativeHaptics").then(({ hapticMedium }) => {
      hapticMedium("submit-post")
    })

    uploadingPostRef.current = true
    const snapshotText = text
    const snapshotImage = postImage
    const snapshotRoomShare = pendingRoomShare

    try {
      await runUpload({
        title: snapshotImage ? "Uploading Post" : "Creating Post",
        onDismissCompose: () => {
          setShowCreatePost(false)
          setPostContent("")
          setPostImage(null)
          setPendingRoomShare(null)
        },
        execute: async (report) => {
          creatingPostRef.current = true
          setCreatingPost(true)

          let imageUrl: string | null = null

          if (snapshotImage) {
            report({ percent: 10, stage: "Processing image…" })
            let uploadFile: File = snapshotImage
            if (snapshotImage.type?.startsWith("image/")) {
              uploadFile = await compressImage(snapshotImage)
            }
            const fileName = `${currentUserId}/${Date.now()}-${uploadFile.name}`

            report({ percent: 18, stage: "Uploading media…" })
            const mediaReport = createMonotonicReporter(report, {
              min: 18,
              max: 72,
            })
            const { error: upErr } = await uploadToSupabaseStorageWithProgress(
              supabase,
              {
                bucket: "profile_posts",
                path: fileName,
                file: uploadFile,
                upsert: true,
                onProgress: (loaded, total) => {
                  mediaReport({
                    percent: mapUploadBytesToPercent(loaded, total, {
                      start: 20,
                      end: 72,
                    }),
                    stage: "Uploading media…",
                  })
                },
              }
            )

            if (upErr) {
              throw new Error(upErr)
            }

            const base = process.env.NEXT_PUBLIC_SUPABASE_URL
            imageUrl = base
              ? `${base}/storage/v1/object/public/profile_posts/${fileName}`
              : null
          } else {
            report({ percent: 40, stage: "Creating post…" })
          }

          const insertPayload = snapshotRoomShare
            ? buildRoomSharePostInsert(
                currentUserId,
                snapshotRoomShare,
                snapshotText,
                imageUrl
              )
            : {
                user_id: currentUserId,
                content: snapshotText || null,
                image_url: imageUrl,
              }

          report({ percent: 82, stage: "Publishing…" })

          const { error } = await supabase
            .from("profile_posts")
            .insert(insertPayload)

          if (error) {
            showPopup(supabaseMutationFeedback(error, "Post Failed"))
            throw new Error(handleSupabaseError(error))
          }

          if (currentUserId) invalidateUserStreaksCache(currentUserId)

          const { data } = await supabase
            .from("profile_posts")
            .select("*")
            .eq("user_id", profile.id)
            .order("created_at", { ascending: false })

          setWallPosts(data || [])
          showPopup(feedbackPresets.postPublished())
          notifyGettingStartedChecklistMaybeCompleted()
          report({ percent: 95, stage: "Finishing…" })
        },
      })
    } catch {
      // Overlay handles retry/cancel.
    } finally {
      creatingPostRef.current = false
      setCreatingPost(false)
      uploadingPostRef.current = false
    }
  }

  const handleReelPublished = useCallback(
    async (reelId: string) => {
      if (!profile?.id) return
      const data = await fetchProfileReels(String(profile.id))
      setProfileReels(data)
      setActiveTab("reels")
      const published = data.find((row) => String(row.id) === String(reelId)) ?? null
      if (published) openReelDetail(published)
      showPopup(feedbackPresets.reelPublished())
    },
    [fetchProfileReels, openReelDetail, profile?.id, showPopup]
  )

  const applyReelPatch = useCallback(
    (reelId: string, patch: Partial<ReelRow>) => {
      setProfileReels((prev) =>
        prev.map((row) =>
          String(row.id) === reelId ? { ...row, ...patch } : row
        )
      )
      setSelectedReelDetail((prev) => {
        if (!prev || String(prev.id) !== reelId) return prev
        return reelDetailFeedItem({ ...prev, ...patch }, profile)
      })
      if (currentUserId) {
        patchFeedReelInSessionsForUser(currentUserId, reelId, patch)
      }
    },
    [currentUserId, profile]
  )

  const handleReelSaved = useCallback(
    (reel: ReelRow) => {
      applyReelPatch(String(reel.id), {
        caption: reel.caption,
        updated_at: reel.updated_at,
      })
      setEditingReel(null)
      setOpenMenuId(null)
    },
    [applyReelPatch]
  )

  const handleStartEditReel = useCallback(
    (post: any) => {
      if (!currentUserId || !profile || currentUserId !== profile.id) return
      if (isTradeAttachedReel(post)) return
      setEditingReel({
        id: String(post.id),
        user_id: String(post.user_id),
        caption: post.caption != null ? String(post.caption) : null,
        video_url: String(post.video_url),
        thumbnail_url: String(post.thumbnail_url),
        duration_seconds:
          post.duration_seconds != null ? Number(post.duration_seconds) : null,
        visibility: post.visibility === "private" ? "private" : "public",
        trade_id: null,
        kind: null,
        created_at: String(post.created_at),
        updated_at: String(post.updated_at ?? post.created_at),
      })
      setOpenMenuId(null)
    },
    [currentUserId, profile]
  )

  const handleReplaceReelVideo = useCallback((post: any) => {
    if (!currentUserId || !profile || currentUserId !== profile.id) return
    if (!isTradeAttachedReel(post)) return
    setReplacingReelPost(post)
    setOpenMenuId(null)
    replaceReelInputRef.current?.click()
  }, [currentUserId, profile])

  const handleReplaceReelFileSelected = useCallback(
    async (file: File | null) => {
      if (!file || !replacingReelPost || !currentUserId) return

      const reelId = String(replacingReelPost.id)
      const snapshotPost = replacingReelPost
      setReplacingReelPost(null)

      try {
        await runUpload({
          title: "Uploading Clip",
          execute: async (report) => {
            const result = await replaceTradeReelVideo(supabase, {
              reelId,
              userId: currentUserId,
              file,
              onProgress: report,
            })

            if ("error" in result) {
              throw new Error(result.error)
            }

            const updated = result.reel
            setProfileReels((prev) =>
              prev.map((row) => (String(row.id) === reelId ? updated : row))
            )
            if (updated.trade_id) {
              setTradeReelsByTradeId((prev) => ({
                ...prev,
                [String(updated.trade_id)]: updated,
              }))
            }
            if (selectedReelDetail && String(selectedReelDetail.id) === reelId) {
              setSelectedReelDetail(
                reelDetailFeedItem(updated as Record<string, unknown>, profile)
              )
            }
            applyReelPatch(reelId, updated)
          },
        })
      } catch {
        setReplacingReelPost(snapshotPost)
      }
    },
    [
      applyReelPatch,
      currentUserId,
      profile,
      replacingReelPost,
      runUpload,
      selectedReelDetail,
    ]
  )

  const performDeleteReel = useCallback(
    async (post: any) => {
      if (!currentUserId || !profile || currentUserId !== profile.id) return
      if (String(post.user_id) !== profile.id) return

      const reelId = String(post.id)
      const result = await deleteReel(supabase, {
        reelId,
        userId: currentUserId,
      })

      if ("error" in result) {
        showPopup({ type: "error", message: handleSupabaseError(result.error) })
        return
      }

      setProfileReels((prev) =>
        prev.filter((row) => String(row.id) !== reelId)
      )
      if (post.trade_id) {
        const tradeId = String(post.trade_id)
        setTradeReelsByTradeId((prev) => {
          const next = { ...prev }
          delete next[tradeId]
          return next
        })
      }
      if (selectedReelDetail && String(selectedReelDetail.id) === reelId) {
        setSelectedReelDetail(null)
      }
      removeFeedReelFromSessionsForUser(currentUserId, reelId)
      setOpenMenuId(null)
    },
    [currentUserId, profile, selectedReelDetail, showPopup]
  )

  const {
    requestDelete: requestDeleteReel,
    confirmModalProps: deleteReelConfirmProps,
  } = useDeleteReelConfirmation(performDeleteReel)

  const posts = wallPosts
  const sortedPosts = [...posts].sort((a, b) => {
    if (a.is_pinned && !b.is_pinned) return -1
    if (!a.is_pinned && b.is_pinned) return 1
    return new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  })

  async function loadPostEngagement(postList: any[]) {
    if (!postList.length) {
      return
    }
    const ids = postList.map((p) => p.id)
    const [{ data: likesRows }, { data: commentsRows }] = await Promise.all([
      supabase
        .from("profile_post_likes")
        .select("profile_post_id, user_id")
        .in("profile_post_id", ids),
      queryProfilePostComments((select) =>
        supabase
          .from("profile_post_comments")
          .select(select)
          .in("profile_post_id", ids)
          .order("created_at", { ascending: true })
      ),
    ])

    const likesMap: Record<string, { count: number; liked: boolean }> = {}
    for (const id of ids) {
      likesMap[String(id)] = { count: 0, liked: false }
    }
    for (const row of likesRows || []) {
      const key = String(row.profile_post_id)
      if (!likesMap[key]) likesMap[key] = { count: 0, liked: false }
      likesMap[key].count += 1
      if (currentUserId && row.user_id === currentUserId) likesMap[key].liked = true
    }

    const commentsMap: Record<string, any[]> = {}
    for (const id of ids) commentsMap[String(id)] = []
    for (const row of commentsRows || []) {
      const key = String(row.profile_post_id)
      if (!commentsMap[key]) commentsMap[key] = []
      commentsMap[key].push(row)
    }

    setLikesByPost((prev) => ({ ...prev, ...likesMap }))
    setCommentsByPost((prev) => ({ ...prev, ...commentsMap }))
  }

  useEffect(() => {
    void loadPostEngagement(posts)
  }, [currentUserId, posts.length])

  useEffect(() => {
    const handleClick = () => {
      setOpenMenuId(null)
    }
    window.addEventListener("click", handleClick)
    return () => window.removeEventListener("click", handleClick)
  }, [])

  async function handleLike(id: string, type: "post" | "trade") {
    if (!currentUserId || type !== "post") return
    const key = String(id)
    if (likeBusyRef.current.has(key) || likeBusyByPost[key]) return

    likeBusyRef.current.add(key)
    setLikeBusyByPost((prev) => ({ ...prev, [key]: true }))

    try {
      const meta = likesByPost[key] || { count: 0, liked: false }
      const postRow = posts.find((p) => String(p.id) === key)
      const ownerId = profilePostOwnerUserId(postRow ?? { user_id: profile?.id })
      await toggleContentLike(supabase, {
        kind: "profile_post",
        contentId: key,
        userId: currentUserId,
        ownerUserId: ownerId,
        meta,
        onMetaChange: (next) => {
          setLikesByPost((prev) => ({ ...prev, [key]: next }))
        },
      })
    } finally {
      likeBusyRef.current.delete(key)
      setLikeBusyByPost((prev) => ({ ...prev, [key]: false }))
    }
  }

  async function submitComment(
    id: string,
    type: "post" | "trade",
    parentCommentId?: string | null
  ) {
    if (!currentUserId || type !== "post") return
    const key = String(id)
    const text = (commentDraft[key] || "").trim()
    if (!text) return
    if (commentSubmittingRef.current.has(key) || commentSubmitting[key]) return

    commentSubmittingRef.current.add(key)
    setCommentSubmitting((s) => ({ ...s, [key]: true }))

    void import("@/lib/nativeHaptics").then(({ hapticMedium }) => {
      hapticMedium("submit-comment")
    })

    try {
    const postRow = posts.find((p) => String(p.id) === key)
    const existingComments = commentsByPost[key] || []
    const insertPayload: Record<string, unknown> = {
      profile_post_id: key,
      user_id: currentUserId,
      content: text,
    }
    if (parentCommentId) {
      insertPayload.parent_comment_id = parentCommentId
    }

    const { data, error } = await supabase
      .from("profile_post_comments")
      .insert(insertPayload)
      .select(PROFILE_POST_COMMENT_INSERT_SELECT)
      .single()
    if (error) return console.error(error)
    const insertedRow = withInsertedProfilePostParentCommentId(data, parentCommentId)
    setCommentsByPost((prev) => ({ ...prev, [key]: [...(prev[key] || []), insertedRow] }))
    setCommentDraft((prev) => ({ ...prev, [key]: "" }))

    const ownerId = profilePostOwnerUserId(postRow ?? { user_id: profile?.id })
    if (ownerId) {
      await insertProfilePostCommentNotifications(supabase, {
        profilePostId: key,
        commentId: String(insertedRow.id),
        ownerUserId: ownerId,
        senderUserId: currentUserId,
        content: text,
        parentCommentId,
        existingComments,
      })
    }
    } finally {
      commentSubmittingRef.current.delete(key)
      setCommentSubmitting((s) => ({ ...s, [key]: false }))
    }
  }

  const buildAchievementPostStub = useCallback(
    (achievement: Achievement, postId: string, createdAt?: string | null) => ({
      id: postId,
      feedKind: "achievement" as const,
      user_id: profile?.id,
      achievement_id: achievement.id,
      created_at: createdAt ?? achievement.created_at ?? achievement.achieved_at,
      achievements: achievement,
      profiles: {
        username: profile?.username ?? null,
        avatar_url: profile?.avatar_url ?? null,
      },
    }),
    [profile?.avatar_url, profile?.id, profile?.username]
  )

  const openAchievementPostModal = useCallback(
    (post: any, focusComments = false) => {
      const postId = String(post.id)
      if (focusComments) {
        feedOpenCommentsRef.current[postId] = true
      }
      setSelectedAchievementPostDetail(post)
    },
    []
  )

  async function handleAchievementLike(postId: string) {
    if (!currentUserId) return
    const key = String(postId)
    if (likeBusyRef.current.has(key) || likeBusyByPost[key]) return

    likeBusyRef.current.add(key)
    setLikeBusyByPost((prev) => ({ ...prev, [key]: true }))

    try {
      const meta = likesByPost[key] || { count: 0, liked: false }
      const ownerId = profile?.id ? String(profile.id) : null
      await toggleContentLike(supabase, {
        kind: "achievement_post",
        contentId: key,
        userId: currentUserId,
        ownerUserId: ownerId,
        meta,
        onMetaChange: (next) => {
          setLikesByPost((prev) => ({ ...prev, [key]: next }))
        },
      })
    } finally {
      likeBusyRef.current.delete(key)
      setLikeBusyByPost((prev) => ({ ...prev, [key]: false }))
    }
  }

  async function submitAchievementPostComment(
    post: any,
    text: string,
    parentCommentId?: string | null
  ) {
    if (!currentUserId) return false
    const key = String(post.id)
    const trimmed = (text || "").trim()
    if (!trimmed) return false
    if (commentSubmittingRef.current.has(key) || commentSubmitting[key]) return false

    commentSubmittingRef.current.add(key)
    setCommentSubmitting((s) => ({ ...s, [key]: true }))

    try {
      const existingComments = commentsByPost[key] || []
      const insertPayload: Record<string, unknown> = {
        achievement_post_id: key,
        user_id: currentUserId,
        content: trimmed,
      }
      if (parentCommentId) {
        insertPayload.parent_comment_id = parentCommentId
      }

      const { data, error } = await supabase
        .from("achievement_post_comments")
        .insert(insertPayload)
        .select(ACHIEVEMENT_POST_COMMENT_INSERT_SELECT)
        .single()

      if (error) {
        console.error(error)
        return false
      }

      const insertedRow = withInsertedAchievementPostParentCommentId(
        data,
        parentCommentId
      )
      setCommentsByPost((prev) => ({
        ...prev,
        [key]: [...(prev[key] || []), insertedRow],
      }))

      const ownerId = achievementPostOwnerUserId(post)
      if (ownerId) {
        await insertAchievementPostCommentNotifications(supabase, {
          achievementPostId: key,
          commentId: String(insertedRow.id),
          ownerUserId: ownerId,
          senderUserId: currentUserId,
          content: trimmed,
          parentCommentId,
          existingComments,
        })
      }

      return true
    } finally {
      commentSubmittingRef.current.delete(key)
      setCommentSubmitting((s) => ({ ...s, [key]: false }))
    }
  }

  async function handleReelLike(postId: string) {
    if (!currentUserId) return
    const key = String(postId)
    if (likeBusyRef.current.has(key) || likeBusyByPost[key]) return

    likeBusyRef.current.add(key)
    setLikeBusyByPost((prev) => ({ ...prev, [key]: true }))

    try {
      const meta = likesByPost[key] || { count: 0, liked: false }
      const ownerId = profile?.id ? String(profile.id) : null

      await toggleReelLike(supabase, {
        reelId: key,
        userId: currentUserId,
        ownerUserId: ownerId,
        meta,
        onMetaChange: (next) => {
          setLikesByPost((prev) => ({ ...prev, [key]: next }))
        },
      })
    } finally {
      likeBusyRef.current.delete(key)
      setLikeBusyByPost((prev) => ({ ...prev, [key]: false }))
    }
  }

  async function submitReelComment(
    post: any,
    text: string,
    parentCommentId?: string | null
  ) {
    if (!currentUserId) return false
    const key = String(post.id)
    const trimmed = (text || "").trim()
    if (!trimmed) return false
    if (commentSubmittingRef.current.has(key) || commentSubmitting[key]) return false

    commentSubmittingRef.current.add(key)
    setCommentSubmitting((s) => ({ ...s, [key]: true }))

    try {
      const existingComments = commentsByPost[key] || []
      const insertPayload: Record<string, unknown> = {
        reel_id: key,
        user_id: currentUserId,
        content: trimmed,
      }
      if (parentCommentId) {
        insertPayload.parent_comment_id = parentCommentId
      }

      const { data, error } = await supabase
        .from("reel_comments")
        .insert(insertPayload)
        .select(REEL_COMMENT_INSERT_SELECT)
        .single()

      if (error) {
        console.error(error)
        return false
      }

      const insertedRow = withInsertedReelParentCommentId(data, parentCommentId)
      setCommentsByPost((prev) => ({
        ...prev,
        [key]: [...(prev[key] || []), insertedRow],
      }))

      const ownerId = profile?.id ? String(profile.id) : null
      if (ownerId) {
        await insertReelCommentNotifications(supabase, {
          reelId: key,
          commentId: String(insertedRow.id),
          ownerUserId: ownerId,
          senderUserId: currentUserId,
          content: trimmed,
          parentCommentId,
          existingComments,
        })
      }

      return true
    } finally {
      commentSubmittingRef.current.delete(key)
      setCommentSubmitting((s) => ({ ...s, [key]: false }))
    }
  }

  function handleShareAchievement(achievement: Achievement, postId: string) {
    setSharePost(buildAchievementPostStub(achievement, postId))
  }

  async function deleteComment(comment: any) {
    if (!currentUserId) {
      devWarn("[comment-delete] aborted: no user")
      return false
    }
    if (String(comment.user_id) !== String(currentUserId)) {
      devWarn("[comment-delete] aborted: not author", {
        commentUserId: comment.user_id,
        currentUserId,
      })
      return false
    }

    const commentId = String(comment.id)
    const profilePostId = comment.profile_post_id
      ? String(comment.profile_post_id)
      : null
    const achievementPostId = comment.achievement_post_id
      ? String(comment.achievement_post_id)
      : null
    const reelId = comment.reel_id ? String(comment.reel_id) : null
    const postId = comment.post_id ? String(comment.post_id) : null
    const tradeId = comment.trade_id ? String(comment.trade_id) : null

    let result:
      | Awaited<ReturnType<typeof deleteProfilePostComment>>
      | Awaited<ReturnType<typeof deleteAchievementPostComment>>
      | Awaited<ReturnType<typeof deleteReelComment>>
      | Awaited<ReturnType<typeof deleteFeedComment>>
      | Awaited<ReturnType<typeof deleteTradeComment>>
    let stateKey: string

    if (profilePostId) {
      result = await deleteProfilePostComment(supabase, {
        id: commentId,
        user_id: currentUserId,
        content: comment.content,
        profile_post_id: profilePostId,
      })
      stateKey = profilePostId
    } else if (achievementPostId) {
      result = await deleteAchievementPostComment(supabase, {
        id: commentId,
        user_id: currentUserId,
        content: comment.content,
        achievement_post_id: achievementPostId,
      })
      stateKey = achievementPostId
    } else if (reelId) {
      result = await deleteReelComment(supabase, {
        id: commentId,
        user_id: currentUserId,
        content: comment.content,
        reel_id: reelId,
      })
      stateKey = reelId
    } else if (postId) {
      result = await deleteFeedComment(supabase, {
        id: commentId,
        user_id: currentUserId,
        content: comment.content,
        post_id: postId,
      })
      stateKey = postId
    } else if (tradeId) {
      result = await deleteTradeComment(supabase, {
        id: commentId,
        user_id: currentUserId,
        content: comment.content,
        trade_id: tradeId,
      })
      stateKey = tradeId
    } else {
      console.error("[comment-delete] aborted: missing comment target", comment)
      return false
    }

    const { error, deleted } = result

    if (error || !deleted) {
      console.error("[comment-delete] failed", {
        commentId,
        userId: currentUserId,
        profilePostId,
        achievementPostId,
        postId,
        tradeId,
        error,
      })
      showPopup({ type: "error", message: handleSupabaseError(error) })
      return false
    }

    setCommentsByPost((prev) => ({
      ...prev,
      [stateKey]: filterCommentsAfterDelete(prev[stateKey] ?? [], commentId),
    }))

    if (feedDeepLinkPost && String(feedDeepLinkPost.id) === stateKey) {
      setFeedDeepLinkComments((prev) =>
        filterCommentsAfterDelete(prev, commentId)
      )
    }

    devLog("[comment-delete] local state updated", {
      commentId,
      stateKey,
    })

    return true
  }

  async function togglePinComment(comment: any, pinned: boolean) {
    if (!currentUserId) return false
    if (comment.parent_comment_id) return false

    const target = resolveCommentPinTarget(comment)
    if (!target) {
      console.error("[comment-pin] aborted: missing comment target", comment)
      return false
    }

    const ownerId = profile?.id ?? null
    if (
      !canPinComment({
        viewerUserId: currentUserId,
        contentOwnerUserId: ownerId,
      })
    ) {
      return false
    }

    const commentId = String(comment.id)
    let previous: any[] = []
    setCommentsByPost((prev) => {
      previous = prev[target.stateKey] ?? []
      return {
        ...prev,
        [target.stateKey]: applyPinnedCommentState(previous, commentId, pinned),
      }
    })

    if (feedDeepLinkPost && String(feedDeepLinkPost.id) === target.stateKey) {
      setFeedDeepLinkComments((prev) =>
        applyPinnedCommentState(prev, commentId, pinned)
      )
    }

    const { error } = await pinCommentByKind(supabase, target.kind, {
      commentId,
      pinned,
      parentCommentId: comment.parent_comment_id ?? null,
    })

    if (error) {
      setCommentsByPost((prev) => ({
        ...prev,
        [target.stateKey]: previous,
      }))
      if (feedDeepLinkPost && String(feedDeepLinkPost.id) === target.stateKey) {
        setFeedDeepLinkComments(previous)
      }
      showPopup({ type: "error", message: handleSupabaseError(error) })
      return false
    }

    return true
  }

  async function handleDeletePost(postId: string) {
    const confirmDelete = window.confirm("Delete this post?")
    if (!confirmDelete) return

    const { error } = await supabase
      .from("profile_posts")
      .delete()
      .eq("id", postId)

    if (error) {
      console.error(error)
      return
    }

    setWallPosts((prev) => prev.filter((p) => String(p.id) !== String(postId)))
    setOpenMenuId(null)
  }

  async function handleUpdatePost() {
    if (!editingPost) return
    const { error } = await supabase
      .from("profile_posts")
      .update({ content: editContent })
      .eq("id", editingPost.id)

    if (error) {
      console.error(error)
      return
    }

    setWallPosts((prev) =>
      prev.map((p) =>
        String(p.id) === String(editingPost.id) ? { ...p, content: editContent } : p
      )
    )
    setEditingPost(null)
  }

  async function handlePinPost(post: any) {
    const { error } = await supabase
      .from("profile_posts")
      .update({ is_pinned: !post.is_pinned })
      .eq("id", post.id)

    if (error) {
      console.error(error)
      return
    }

    setWallPosts((prev) =>
      prev.map((p) =>
        String(p.id) === String(post.id) ? { ...p, is_pinned: !p.is_pinned } : p
      )
    )
    setOpenMenuId(null)
  }

  function handleSharePost(post: any) {
    setSharePost(post)
  }

  async function handleSavePost(postId: string) {
    if (!currentUserId) return
    setOpenMenuId(null)
    const { error } = await supabase.from("saved_posts").insert({
      user_id: currentUserId,
      post_id: postId,
    })
    if (error && error.code !== "23505") {
      console.error(error)
      showPopup({ type: "error", message: "Could not save post." })
    }
  }

  function openEditTradeModal(trade: any) {
    setEditingTrade({ ...trade })
  }

  async function handlePinTrade(trade: any) {
    const nextPinned = !trade.is_pinned
    const prevPinned = trade.is_pinned
    setAllTrades((prev) =>
      prev.map((t) =>
        String(t.id) === String(trade.id) ? { ...t, is_pinned: nextPinned } : t
      )
    )
    setAnalyticsTradeRows((prev) =>
      prev.map((t) =>
        String(t.id) === String(trade.id) ? { ...t, is_pinned: nextPinned } : t
      )
    )

    const { error } = await supabase
      .from("trades")
      .update({ is_pinned: nextPinned })
      .eq("id", trade.id)

    if (error) {
      console.error(error)
      setAllTrades((prev) =>
        prev.map((t) =>
          String(t.id) === String(trade.id) ? { ...t, is_pinned: prevPinned } : t
        )
      )
      setAnalyticsTradeRows((prev) =>
        prev.map((t) =>
          String(t.id) === String(trade.id) ? { ...t, is_pinned: prevPinned } : t
        )
      )
    }
  }

  const performDeleteTrade = useCallback(async (tradeId: string) => {
    if (isDemoModeActive()) {
      requestDemoSignup("delete")
      return
    }
    const snapshotAll = allTrades
    const snapshotAnalytics = analyticsTradeRows
    const snapshotSummary = summaryTrades
    setAllTrades((prev) => prev.filter((t) => String(t.id) !== String(tradeId)))
    setAnalyticsTradeRows((prev) =>
      prev.filter((t) => String(t.id) !== String(tradeId))
    )
    setSummaryTrades((prev) =>
      prev.filter((t) => String(t.id) !== String(tradeId))
    )
    setSelectedTradeDetail((prev) =>
      prev && String(prev.id) === String(tradeId) ? null : prev
    )
    try {
      await deleteUserTrade(supabase, tradeId)
    } catch (err) {
      console.error(err)
      setAllTrades(snapshotAll)
      setAnalyticsTradeRows(snapshotAnalytics)
      setSummaryTrades(snapshotSummary)
    }
  }, [allTrades, analyticsTradeRows, summaryTrades])

  const { requestDelete: handleDeleteTrade, confirmModalProps: deleteTradeConfirmProps } =
    useDeleteTradeConfirmation(performDeleteTrade)

  const emptyFollowSet = useMemo(() => new Set<string>(), [])

  const profileFollowingIds = useMemo(() => {
    if (!profile?.id || !isFollowing) return emptyFollowSet
    return new Set([profile.id])
  }, [profile?.id, isFollowing, emptyFollowSet])

  const profileRequestedIds = useMemo(() => {
    if (!profile?.id || !isRequested) return emptyFollowSet
    return new Set([profile.id])
  }, [profile?.id, isRequested, emptyFollowSet])

  const profileFollowsYouIds = useMemo(() => {
    if (!profile?.id || !followsYou) return emptyFollowSet
    return new Set([profile.id])
  }, [profile?.id, followsYou, emptyFollowSet])

  const handleProfileFollowingChange = useCallback(
    async (_targetId: string, following: boolean) => {
      setIsFollowing(following)
      if (!profile) return

      // Follow graph changed — drop session caches so modals stay accurate.
      invalidateFollowListCache(profile.id)
      if (currentUserId) invalidateFollowListCache(currentUserId)

      if (!following && profile.is_private === true) {
        setAllTrades([])
        setVisibleTradeCount(PAGE_SIZE)
      } else if (following && profile.is_private === true) {
        setVisibleTradeCount(PAGE_SIZE)
      }

      const { count: followersN } = await supabase
        .from("followers")
        .select("*", { count: "exact", head: true })
        .eq("following_id", profile.id)

      setFollowersCount(followersN ?? 0)
    },
    [profile, currentUserId]
  )

  const handleProfileRequestedChange = useCallback(
    (_targetId: string, requested: boolean) => {
      setIsRequested(requested)
    },
    []
  )

  const clearProfileQueryParams = useCallback(() => {
    if (!profile) return
    router.replace(profilePath(profile), { scroll: false })
  }, [profile, router])

  const loadFeedPostEngagement = useCallback(
    async (postId: string, openComments = false) => {
      const [{ data: likesRows }, { data: commentsRows }] = await Promise.all([
        supabase.from("likes").select("post_id, user_id").eq("post_id", postId),
        queryFeedComments((select) =>
          supabase
            .from("comments")
            .select(select)
            .eq("post_id", postId)
            .order("created_at", { ascending: true })
        ),
      ])

      let count = 0
      let liked = false
      for (const row of likesRows || []) {
        count += 1
        if (currentUserId && row.user_id === currentUserId) liked = true
      }

      setFeedDeepLinkLikeMeta({ count, liked })
      setFeedDeepLinkComments(commentsRows || [])
      if (openComments) {
        feedOpenCommentsRef.current[postId] = true
      }
    },
    [currentUserId]
  )

  const openFeedPostDeepLink = useCallback(
    async (postId: string, openComments = false) => {
      if (!profile?.id || !canViewTrades) {
        clearProfileQueryParams()
        return
      }

      const { data: feedPost, error } = await supabase
        .from("posts")
        .select(FEED_POSTS_SELECT)
        .eq("id", postId)
        .maybeSingle()

      if (error || !feedPost) {
        clearProfileQueryParams()
        return
      }

      const tradeJoin = feedPost?.trades
      const tradeRow = tradeJoin
        ? Array.isArray(tradeJoin)
          ? tradeJoin[0]
          : tradeJoin
        : null
      const ownerId = tradeRow?.user_id ?? feedPost.user_id
      if (ownerId && profile?.id && String(ownerId) !== String(profile.id)) {
        clearProfileQueryParams()
        return
      }

      await loadFeedPostEngagement(postId, openComments)
      setFeedDeepLinkPost(feedPost)
      clearProfileQueryParams()
    },
    [canViewTrades, clearProfileQueryParams, loadFeedPostEngagement, profile?.id]
  )

  const openTradeDeepLink = useCallback(
    async (tradeId: string) => {
      if (!profile?.id || !canViewTrades) {
        clearProfileQueryParams()
        return
      }

      setActiveTab("trades")

      let trade =
        trades.find((row) => String(row.id) === tradeId) ??
        allTrades.find((row) => String(row.id) === tradeId)

      if (!trade) {
        const isOwner =
          currentUserId != null && String(currentUserId) === String(profile.id)
        const { data, error } = await supabase
          .from("trades")
          .select(isOwner ? "*" : PUBLIC_TRADE_SELECT)
          .eq("id", tradeId)
          .eq("user_id", profile.id)
          .eq("is_public", true)
          .maybeSingle()

        if (error || !data) {
          clearProfileQueryParams()
          return
        }
        trade = sanitizeTradeForViewer(data, { isOwner }) as typeof data
        setAllTrades((prev) => mergeUniqueById(prev, [trade]))
      }

      setSelectedTradeDetail({ ...trade, currentUserId })
      scrollToProfileTarget(`trade-${tradeId}`)
      clearProfileQueryParams()
    },
    [
      allTrades,
      canViewTrades,
      clearProfileQueryParams,
      currentUserId,
      profile?.id,
      trades,
    ]
  )

  const openProfilePostDeepLink = useCallback(
    (postId: string, focusComments = false) => {
      const wallPost = wallPosts.find((row) => String(row.id) === postId)
      if (!wallPost) return false

      setActiveTab("posts")
      setPostDetailFocusComments(focusComments)
      setSelectedPostDetail(wallPost)
      clearProfileQueryParams()
      return true
    },
    [clearProfileQueryParams, wallPosts]
  )

  const openAchievementPostDeepLink = useCallback(
    async (postId: string, focusComments = false) => {
      const achievement = achievements.find(
        (row) => achievementPostIds[String(row.id)] === postId
      )

      if (achievement) {
        setActiveTab("achievements")
        openAchievementPostModal(
          buildAchievementPostStub(achievement, postId),
          focusComments
        )
        clearProfileQueryParams()
        return true
      }

      const fetched = await fetchAchievementPostById(supabase, postId)
      if (!fetched || String(fetched.user_id) !== String(profile?.id ?? "")) {
        return false
      }

      const { likesMap, commentsMap } = await loadAchievementPostEngagementMaps(
        supabase,
        [postId],
        currentUserId
      )
      setLikesByPost((prev) => ({ ...prev, ...likesMap }))
      setCommentsByPost((prev) => ({ ...prev, ...commentsMap }))

      setActiveTab("achievements")
      openAchievementPostModal(fetched, focusComments)
      clearProfileQueryParams()
      return true
    },
    [
      achievementPostIds,
      achievements,
      buildAchievementPostStub,
      clearProfileQueryParams,
      currentUserId,
      openAchievementPostModal,
      profile?.id,
    ]
  )

  useEffect(() => {
    if (!profile?.id || loading) return

    const postParam = searchParams.get("post")?.trim()
    const achievementParam = searchParams.get("achievement")?.trim()
    const reelParam = searchParams.get("reel")?.trim()
    const tradeParam = searchParams.get("trade")?.trim()
    const openComments = searchParams.get("comments") === "1"
    const tabParam = searchParams.get("tab")?.trim()
    const requestedTab =
      reelParam
        ? "reels"
        : postParam
          ? "posts"
          : achievementParam
            ? "achievements"
            : tradeParam
              ? "trades"
              : tabParam
    if (
      requestedTab === "trades" ||
      requestedTab === "reels" ||
      requestedTab === "posts" ||
      requestedTab === "calendar" ||
      requestedTab === "stats" ||
      requestedTab === "achievements"
    ) {
      setActiveTab(requestedTab)
    }
    if (postParam && !wallPostsReady) return
    if (reelParam && !profileReelsReady) return
    const key = reelParam
      ? `reel:${reelParam}:${openComments ? "1" : "0"}`
      : achievementParam
      ? `achievement:${achievementParam}:${openComments ? "1" : "0"}`
      : postParam
      ? `post:${postParam}:${openComments ? "1" : "0"}`
      : tradeParam
        ? `trade:${tradeParam}`
        : null

    if (!key || deepLinkHandledRef.current === key) return
    deepLinkHandledRef.current = key

    void (async () => {
      if (reelParam) {
        setActiveTab("reels")
        const reel =
          profileReels.find((row) => String(row.id) === reelParam) ?? null
        if (reel) {
          openReelDetail(reel, openComments)
        }
        return
      }

      if (achievementParam) {
        await openAchievementPostDeepLink(achievementParam, openComments)
        return
      }

      if (postParam) {
        if (!openProfilePostDeepLink(postParam, openComments)) {
          await openFeedPostDeepLink(postParam, openComments)
        }
        return
      }

      if (tradeParam) {
        await openTradeDeepLink(tradeParam)
      }
    })()
  }, [
    loading,
    openFeedPostDeepLink,
    openProfilePostDeepLink,
    openAchievementPostDeepLink,
    openReelDetail,
    openTradeDeepLink,
    profile?.id,
    profileReels,
    profileReelsReady,
    searchParams,
    wallPostsReady,
  ])

  useEffect(() => {
    if (!profile?.id || !currentUserId || loading) return
    if (searchParams.get("followers") !== "1") return
    if (String(profile.id) !== String(currentUserId)) return

    void openFollowersModal()
    clearProfileQueryParams()
  }, [
    clearProfileQueryParams,
    currentUserId,
    loading,
    profile?.id,
    searchParams,
  ])

  useEffect(() => {
    if (!profile?.id || !currentUserId || loading) return
    if (searchParams.get("createPost") !== "1") return
    if (String(profile.id) !== String(currentUserId)) return

    const roomId = searchParams.get("shareRoom")?.trim() ?? ""

    async function openComposer() {
      setActiveTab("posts")

      if (roomId) {
        let draft: PendingRoomShareDraft | null = null

        try {
          const cached = sessionStorage.getItem("pendingRoomShareDraft")
          if (cached) {
            const parsed = JSON.parse(cached) as PendingRoomShareDraft
            if (parsed?.roomId === roomId) {
              draft = parsed
              sessionStorage.removeItem("pendingRoomShareDraft")
            }
          }
        } catch {
          // ignore invalid session draft
        }

        if (!draft) {
          const { data, error } = await supabase
            .from("rooms")
            .select("id, name, description, image_url")
            .eq("id", roomId)
            .maybeSingle()

          if (error || !data) {
            showPopup(
              persistentError(
                "Room Unavailable",
                "Could not load this room for sharing."
              )
            )
            clearProfileQueryParams()
            return
          }

          draft = pendingRoomShareFromRoom(data)
        }

        setPendingRoomShare(draft)
      }

      openCreatePostModal()
      clearProfileQueryParams()
    }

    void openComposer()
  }, [
    clearProfileQueryParams,
    currentUserId,
    loading,
    openCreatePostModal,
    profile?.id,
    searchParams,
    showPopup,
  ])

  const toggleFeedDeepLinkLike = useCallback(
    async (post: any) => {
      if (!currentUserId || feedDeepLinkLikeBusyRef.current) return
      const pid = String(post.id)
      const meta = feedDeepLinkLikeMeta
      const ownerId = postTradeOwnerUserId(post)

      feedDeepLinkLikeBusyRef.current = true

      try {
      if (meta.liked) {
        const { error } = await supabase
          .from("likes")
          .delete()
          .eq("post_id", pid)
          .eq("user_id", currentUserId)
        if (error) return
        if (ownerId) {
          refreshLikeNotificationUi()
        }
        setFeedDeepLinkLikeMeta({
          count: Math.max(0, meta.count - 1),
          liked: false,
        })
        return
      }

      const { error } = await supabase
        .from("likes")
        .insert({ post_id: pid, user_id: currentUserId })
      if (error) return
      setFeedDeepLinkLikeMeta({ count: meta.count + 1, liked: true })

      if (ownerId && String(ownerId) !== currentUserId) {
        await ensureLikeNotification(supabase, {
          recipientUserId: String(ownerId),
          senderUserId: currentUserId,
          target: { kind: "post", postId: pid, tradeId: post.trade_id ?? null },
        })
      }
      } finally {
        feedDeepLinkLikeBusyRef.current = false
      }
    },
    [currentUserId, feedDeepLinkLikeMeta]
  )

  const submitFeedDeepLinkComment = useCallback(
    async (post: any, text: string) => {
      if (!currentUserId || feedDeepLinkCommentSubmittingRef.current) return false
      const pid = String(post.id)
      const trimmed = (text || "").trim()
      if (!trimmed) return false

      feedDeepLinkCommentSubmittingRef.current = true
      setFeedDeepLinkCommentSubmitting(true)

      try {
      const { data, error } = await supabase
        .from("comments")
        .insert({
          post_id: pid,
          user_id: currentUserId,
          content: trimmed,
        })
        .select(FEED_COMMENT_INSERT_SELECT)
        .single()

      if (error) {
        console.error(error)
        return false
      }

      setFeedDeepLinkComments((prev) => [...prev, data])

      const ownerId = postTradeOwnerUserId(post)
      await ensureCommentNotificationsForInsert(supabase, {
        commentId: String(data.id),
        senderUserId: currentUserId,
        content: trimmed,
        target: { kind: "post", postId: pid, tradeId: post.trade_id ?? null },
        ownerUserId: ownerId,
        existingComments: feedDeepLinkComments,
      })

      return true
      } finally {
        feedDeepLinkCommentSubmittingRef.current = false
        setFeedDeepLinkCommentSubmitting(false)
      }
    },
    [currentUserId, feedDeepLinkComments]
  )

  const {
    sortedTrades,
    filteredTrades,
    statsVisible,
    overviewStatsVisible,
    biggestWin,
    biggestLoss,
    longTrades,
    equityData,
    currentEquity,
    overviewTotalTrades,
    overviewWinRate,
    overviewTotalPnL,
    overviewAvgRR,
    overviewPayoutTotal,
    currentStreakLabel,
    profitFactor,
    avgWinner,
    avgLoser,
    profitPerTrade,
    maxWinStreak,
    maxLossStreak,
    sessionTotal,
    sessionBreakdown,
  } = useProfileStatistics({
    visibleTrades: trades,
    analyticsTradeRows,
    summaryTrades,
    selectedMode,
    canViewTrades,
    analyticsTradesReady,
    analyticsTradesLoading,
    summaryReady,
    achievements,
    achievementsReady,
  })

  const isMobileViewport = useMaxMdViewport()

  // Mobile grid expects ~12 tiles initially; top up when cache/desktop fetch left fewer.
  useEffect(() => {
    if (!isMobileViewport) return
    if (!profile?.id || !canViewTrades || !tradesReady) return
    if (!tradeHasMore || tradesLoading) return
    if (allTrades.length >= PROFILE_TRADES_PAGE_SIZE_MOBILE) return
    void loadMoreTrades()
  }, [
    allTrades.length,
    canViewTrades,
    isMobileViewport,
    loadMoreTrades,
    profile?.id,
    tradeHasMore,
    tradesLoading,
    tradesReady,
  ])

  const openTradeDetail = useCallback(
    (trade: (typeof sortedTrades)[number], focusComments = false) => {
      setTradeDetailFocusComments(focusComments)
      setSelectedTradeDetail({ ...trade, currentUserId })
    },
    [currentUserId]
  )

  const openTradeDetailFromGrid = useCallback(
    (trade: (typeof sortedTrades)[number]) => {
      openTradeDetail(trade, false)
    },
    [openTradeDetail]
  )

  const selectedTradeIndex = useMemo(() => {
    if (!selectedTradeDetail?.id) return -1
    return sortedTrades.findIndex(
      (row) => String(row.id) === String(selectedTradeDetail.id)
    )
  }, [selectedTradeDetail?.id, sortedTrades])

  const goToAdjacentTrade = useCallback(
    (direction: -1 | 1) => {
      if (selectedTradeIndex < 0) return
      const next = sortedTrades[selectedTradeIndex + direction]
      if (!next) return
      setTradeDetailFocusComments(false)
      setScreenshotLightboxUrl(null)
      setSelectedTradeDetail({ ...next, currentUserId })
    },
    [currentUserId, selectedTradeIndex, sortedTrades]
  )

  const tradeDetailSwipe = useMobileTradeDetailSwipe({
    enabled: isMobileViewport && selectedTradeDetail != null,
    onPrev: () => goToAdjacentTrade(-1),
    onNext: () => goToAdjacentTrade(1),
  })

  if (!profileId) {
    return (
      <>
        <div className="w-full flex items-center justify-center text-red-400">
          Invalid profile
        </div>
      </>
    )
  }

  if (loading) {
    return (
      <>
        <SkeletonProfilePage />
      </>
    )
  }

  if (!profile) {
    const showFetchDebug =
      process.env.NODE_ENV === "development" ||
      process.env.NEXT_PUBLIC_PROFILE_FETCH_DEBUG === "1"

    if (showFetchDebug) {
      return (
        <>
          <div className="mx-auto max-w-lg px-4 py-8 text-center text-red-400">
            <div>Profile not found (debug)</div>
            {lastProfileFetchError ? (
              <p className="mt-3 text-left text-xs font-mono text-red-300/90 whitespace-pre-wrap break-all">
                {lastProfileFetchError}
              </p>
            ) : null}
            <p className="mt-3 text-xs text-gray-400">
              Compare NEXT_PUBLIC_SUPABASE_URL with production. If the list probe
              in the console shows rows but this id returns nothing, suspect RLS
              or a UUID that exists only in the other project.
            </p>
          </div>
        </>
      )
    }

    return (
      <>
        <div className="w-full flex items-center justify-center text-red-400">
          User not found
        </div>
      </>
    )
  }

  const isOwnProfile = currentUserId === profile.id
  const ownedRoom =
    room && room.owner_user_id === profile.id ? room : null
  const hasRoom = !!ownedRoom
  const profileRoomKey =
    ownedRoom?.slug != null && String(ownedRoom.slug).trim() !== ""
      ? String(ownedRoom.slug)
      : ownedRoom?.id != null
        ? String(ownedRoom.id)
        : null
  const canShowVisitorRoomCta =
    canViewTrades &&
    ownedRoom != null &&
    ownedRoom.show_on_profile !== false &&
    profileRoomKey != null

  return (
    <>
      <FeedbackModal {...feedbackModalProps} />
      <ConfirmModal {...deleteTradeConfirmProps} />
      <ConfirmModal {...deleteReelConfirmProps} />
      {currentUserId === profile?.id ? (
        <StoryComposeModal
          open={storyComposeOpen}
          posting={postingStory}
          profile={
            profile
              ? {
                  id: currentUserId,
                  username: profile.username,
                  avatar_url: profile.avatar_url,
                }
              : null
          }
          previewUrl={pendingStoryPreviewUrl}
          onClose={closeStoryCompose}
          onPost={() => void handlePostStory()}
          onReplaceImage={(file) => void setStoryDraft(file)}
        />
      ) : null}
      {currentUserId === profile?.id ? (
        <ReelComposerModal
          open={showReelComposer || editingReel != null}
          userId={currentUserId}
          editReel={editingReel}
          onClose={() => {
            setShowReelComposer(false)
            setEditingReel(null)
          }}
          onPublished={(reelId) => void handleReelPublished(reelId)}
          onSaved={handleReelSaved}
        />
      ) : null}
      {currentUserId === profile?.id ? (
        <QuickTradeModal
          open={showQuickTrade}
          userId={currentUserId}
          onClose={() => setShowQuickTrade(false)}
          onSaved={() => {
            setVisibleTradeCount(PAGE_SIZE)
            void refreshProfileMedia()
          }}
        />
      ) : null}

      <input
        ref={replaceReelInputRef}
        type="file"
        accept="video/mp4,video/quicktime,.mp4,.mov"
        className="hidden"
        onChange={(e) => {
          const file = e.target.files?.[0] ?? null
          e.target.value = ""
          void handleReplaceReelFileSelected(file)
        }}
      />

      {profileStoryOpen && profile?.id && profileCurrentStory ? (
        <FeedStoryViewer
          activeStoryUser={String(profile.id)}
          users={profileStoryBarUsers}
          storiesByUser={profileStoriesByUser}
          currentStories={profileStorySlides}
          currentStoryIndex={profileStoryIndex}
          currentStory={profileCurrentStory}
          currentUserId={currentUserId}
          canGoPrevSlide={profileStoryIndex > 0}
          canGoNextSlide={profileStoryIndex < profileStorySlides.length - 1}
          canGoPrevUser={false}
          canGoNextUser={false}
          onClose={() => {
            setProfileStoryOpen(false)
            setProfileStoryIndex(0)
          }}
          onPrevSlide={() =>
            setProfileStoryIndex((prev) => Math.max(0, prev - 1))
          }
          onNextSlide={() =>
            setProfileStoryIndex((prev) =>
              Math.min(profileStorySlides.length - 1, prev + 1)
            )
          }
          onPrevUser={() => {}}
          onNextUser={() => {}}
          onStoryReplyError={(message) =>
            showPopup({ type: "error", message })
          }
        />
      ) : null}

      <div className="w-full text-gray-100">
        <NativeIosPullToRefresh
          onRefresh={async () => {
            if (!profileId) return
            await Promise.all([
              refreshProfileInBackground(profileId),
              refreshProfileMedia(),
            ])
          }}
        >
        <div className="mx-auto max-w-5xl space-y-2 pt-3 pb-6 pl-[max(0.5rem,env(safe-area-inset-left,0px))] pr-[max(0.5rem,env(safe-area-inset-right,0px))] sm:space-y-4 sm:px-6 sm:pt-4 lg:px-8">
          <PlatformProfileHeader
            profile={profile}
            currentUserId={currentUserId}
            storyTriggerRef={profileStoryTriggerRef}
            hasActiveStory={profileHasActiveStory}
            followersCount={followersCount}
            followingCount={followingCount}
            metaLoading={metaLoading}
            followingIds={profileFollowingIds}
            requestedIds={profileRequestedIds}
            followsYouIds={profileFollowsYouIds}
            messageBusy={messageBusy}
            hasRoom={hasRoom}
            canShowVisitorRoomCta={canShowVisitorRoomCta}
            onStoryFileSelect={(event) => void handleStoryFileSelect(event)}
            onOpenStory={() => {
              setProfileStoryIndex(0)
              setProfileStoryOpen(true)
            }}
            onFollowingChange={handleProfileFollowingChange}
            onRequestedChange={handleProfileRequestedChange}
            onMessage={handleMessage}
            onOpenFollowers={() => void openFollowersModal()}
            onOpenFollowing={() => void openFollowingModal()}
            onEditProfile={() => router.push("/settings#profile")}
            onCreateStory={openCreateStory}
            onCreatePost={openCreatePostModal}
            onCreateReel={openCreateReelModal}
            onCreateQuickTrade={openQuickTradeModal}
            onCreateRoom={() => router.push("/community?create=true")}
            onViewRoom={() =>
              router.push(
                `/community?room=${encodeURIComponent(profileRoomKey!)}`
              )
            }
          />

          <ProfileOverviewStats
            visible={overviewStatsVisible}
            isPrivate={profile.is_private === true}
            totalTrades={overviewTotalTrades}
            winRate={overviewWinRate}
            totalPnl={overviewTotalPnL}
            payoutTotal={overviewPayoutTotal}
            averageRr={overviewAvgRR}
            streakLabel={currentStreakLabel}
          />

          <ProfileTabs activeTab={activeTab} onTabChange={setActiveTab} />

          <div className="mt-2 space-y-6 sm:mt-3 md:mt-4">
            {activeTab === "trades" && (
              <ProfileTradesTab
                trades={sortedTrades}
                loading={tradesLoading}
                isOwnProfile={isOwnProfile}
                canView={canViewTrades}
                hasMore={hasMore}
                onLoadMore={loadMoreTrades}
                onOpenTrade={openTradeDetailFromGrid}
                renderTrade={(trade) => (
                  <TradeCard
                    trade={trade}
                    profile={profile}
                    currentUserId={currentUserId}
                    shareProfile={viewerShareProfile}
                    canManageTrade={currentUserId === profile.id}
                    attachedReel={
                      tradeReelsByTradeId[String(trade.id)] ?? null
                    }
                    onOpenReplay={() => {
                      const reel = tradeReelsByTradeId[String(trade.id)]
                      if (reel) openReelDetail(reel)
                    }}
                    onStartEditTrade={() => openEditTradeModal(trade)}
                    onTogglePinTrade={() => void handlePinTrade(trade)}
                    onDeleteTrade={() =>
                      void handleDeleteTrade(String(trade.id))
                    }
                    showInteractions
                    onOpenDetail={() => openTradeDetail(trade, false)}
                    onOpenComments={() => openTradeDetail(trade, true)}
                  />
                )}
              />
            )}

            {activeTab === "reels" && (
              <ProfileReelsTab
                ready={profileReelsReady}
                reels={profileReels}
                isOwnProfile={isOwnProfile}
                canView={canViewTrades}
                onCreateReel={openCreateReelModal}
                onOpenReel={openReelDetail}
              />
            )}

            {activeTab === "posts" && (
              <ProfilePostsTab
                posts={sortedPosts}
                ready={wallPostsReady}
                isOwnProfile={isOwnProfile}
                canView={canViewTrades}
                onCreateStory={openCreateStory}
                onCreatePost={openCreatePostModal}
                onCreateReel={openCreateReelModal}
                onCreateQuickTrade={openQuickTradeModal}
                renderPost={(post) => {
                  const key = String(post.id)
                  return (
                    <PostCard
                      post={post}
                      profile={profile}
                      canManagePost={currentUserId === profile.id}
                      menuOpen={openMenuId === key}
                      onMenuToggle={() =>
                        setOpenMenuId((prev) => (prev === key ? null : key))
                      }
                      onStartEditPost={() => {
                        setEditingPost(post)
                        setEditContent(post.content || "")
                        setOpenMenuId(null)
                      }}
                      onTogglePinPost={() => void handlePinPost(post)}
                      onSavePost={() => void handleSavePost(key)}
                      onDeletePost={() => void handleDeletePost(key)}
                      showInteractions
                      onLike={() => void handleLike(key, "post")}
                      likeBusy={!!likeBusyByPost[key]}
                      onOpenComments={() => {
                        setPostDetailFocusComments(true)
                        setSelectedPostDetail(post)
                      }}
                      onOpenDetail={() => {
                        setPostDetailFocusComments(false)
                        setSelectedPostDetail(post)
                      }}
                      likeMeta={
                        likesByPost[key] || { count: 0, liked: false }
                      }
                      comments={commentsByPost[key] || []}
                      commentText={commentDraft[key] || ""}
                      onCommentChange={(value) =>
                        setCommentDraft((prev) => ({
                          ...prev,
                          [key]: value,
                        }))
                      }
                      onCommentSubmit={(parentCommentId) =>
                        void submitComment(key, "post", parentCommentId)
                      }
                      commentSubmitting={!!commentSubmitting[key]}
                      currentUserId={currentUserId}
                      onDeleteComment={deleteComment}
                      onTogglePinComment={togglePinComment}
                      onSharePost={
                        currentUserId ? handleSharePost : undefined
                      }
                    />
                  )
                }}
              />
            )}

            {activeTab === "calendar" && (
              <ProfileCalendarTab
                canView={canViewTrades}
                loading={
                  analyticsTradesLoading || !analyticsTradesReady
                }
                trades={filteredTrades}
                isOwnProfile={isOwnProfile}
              />
            )}

            {activeTab === "stats" && (
              <ProfileStatisticsTab
                canView={canViewTrades}
                loading={
                  analyticsTradesLoading || !analyticsTradesReady
                }
                selectedMode={selectedMode}
                onModeChange={setSelectedMode}
                filteredTradesCount={filteredTrades.length}
                statsVisible={statsVisible}
                profitFactor={profitFactor}
                averageWinner={avgWinner}
                averageLoser={avgLoser}
                profitPerTrade={profitPerTrade}
                biggestWin={biggestWin}
                biggestLoss={biggestLoss}
                longTrades={longTrades}
                maxWinStreak={maxWinStreak}
                maxLossStreak={maxLossStreak}
                sessionTotal={sessionTotal}
                sessionBreakdown={sessionBreakdown}
                currentEquity={currentEquity}
                equityData={equityData}
                equityChartNarrow={equityChartNarrow}
              />
            )}

            {activeTab === "achievements" && (
              <ProfileAchievementsTab
                ready={achievementsReady}
                achievements={achievements}
                profileUserId={String(profile.id)}
                currentUserId={currentUserId}
                achievementPostIds={achievementPostIds}
                likesByPost={likesByPost}
                likeBusyByPost={likeBusyByPost}
                commentsByPost={commentsByPost}
                onOpenDetail={setSelectedAchievementDetail}
                onLike={(postId) => void handleAchievementLike(postId)}
                onOpenPost={(achievement, postId, focusComments) =>
                  openAchievementPostModal(
                    buildAchievementPostStub(achievement, postId),
                    focusComments
                  )
                }
                onShare={(achievement, postId) =>
                  handleShareAchievement(achievement, postId)
                }
              />
            )}
          </div>

        </div>
        </NativeIosPullToRefresh>

      </div>

      {showCreatePost &&
        profile &&
        currentUserId === profile.id && (
          <div
            className="fixed inset-0 z-[100] flex items-center justify-center bg-black/70 p-4 backdrop-blur-md"
            role="presentation"
            onClick={() => {
              setShowCreatePost(false)
              setPostContent("")
              setPostImage(null)
              setPendingRoomShare(null)
            }}
          >
            <div
              className="w-full max-w-[400px] rounded-xl border border-white/10 bg-[#0f172a] p-6 shadow-2xl"
              role="dialog"
              aria-modal="true"
              aria-labelledby="create-post-title"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="mb-3 flex items-center justify-between">
                <h2
                  id="create-post-title"
                  className="text-lg font-semibold text-white"
                >
                  Create Post
                </h2>

                <button
                  type="button"
                  onClick={() => {
                    setShowCreatePost(false)
                    setPostContent("")
                    setPostImage(null)
                    setPendingRoomShare(null)
                  }}
                  className="rounded p-1.5 text-gray-400 hover:bg-white/10 hover:text-white"
                  aria-label="Close"
                >
                  ✕
                </button>
              </div>

              <textarea
                value={postContent}
                onChange={(e) => setPostContent(e.target.value)}
                placeholder={
                  pendingRoomShare
                    ? "Add a caption for your room share (optional)"
                    : "What's on your mind?"
                }
                rows={4}
                className="mb-3 w-full resize-none rounded-lg border border-white/10 bg-[#020617] p-2 text-sm text-white placeholder:text-gray-400"
              />

              {pendingRoomShare ? (
                <div className="mb-3">
                  <FeedRoomShareCard
                    post={{
                      room_id: pendingRoomShare.roomId,
                      room_name: pendingRoomShare.roomName,
                      room_logo: pendingRoomShare.roomLogo,
                      room_description: pendingRoomShare.roomDescription,
                    }}
                    viewerUserId={currentUserId}
                  />
                </div>
              ) : null}

              {postImagePreviewUrl ? (
                <div className="mb-3 flex flex-col items-center">
                  <img
                    src={postImagePreviewUrl}
                    alt="Selected image preview"
                    className="max-h-48 w-full rounded-xl border border-white/10 object-contain"
                  />
                  {postImage ? (
                    <p className="mt-1.5 text-xs text-gray-400">
                      {formatPostFileSize(postImage.size)}
                    </p>
                  ) : null}
                </div>
              ) : null}

              <input
                type="file"
                accept="image/*"
                onChange={(e) =>
                  postImageCrop.handleFileSelected(e.target.files?.[0])
                }
                className="mb-3 block w-full text-sm text-gray-300 file:mr-2 file:rounded file:border-0 file:bg-white/10 file:px-3 file:py-1.5 file:text-sm file:text-gray-100"
              />

              <button
                type="button"
                onClick={() => void handleCreatePost()}
                disabled={creatingPost || uploadingPostRef.current}
                className="w-full rounded-lg bg-blue-500 px-3 py-2 text-sm font-medium text-white hover:bg-blue-600 disabled:opacity-50"
              >
                Post
              </button>
            </div>
          </div>
        )}

      {selectedAchievementDetail ? (
        <AchievementDetailModal
          achievement={selectedAchievementDetail}
          onClose={() => setSelectedAchievementDetail(null)}
        />
      ) : null}

      {selectedTradeDetail ? (
        <DetailModalShell
          ariaLabel="Trade details"
          title="Trade"
          layout="split"
          backdropClassName="bg-black/75 backdrop-blur-md"
          onClose={() => {
            setSelectedTradeDetail(null)
            setTradeDetailFocusComments(false)
            setScreenshotLightboxUrl(null)
          }}
        >
          <div
            className="flex min-h-0 flex-1 flex-col overflow-hidden"
            onTouchStart={tradeDetailSwipe.onTouchStart}
            onTouchEnd={tradeDetailSwipe.onTouchEnd}
          >
            <TradeCard
              key={String(selectedTradeDetail.id)}
              inDetailModal
              trade={selectedTradeDetail}
              profile={profile}
              currentUserId={currentUserId}
              shareProfile={viewerShareProfile}
              canManageTrade={currentUserId === profile.id}
              attachedReel={
                tradeReelsByTradeId[String(selectedTradeDetail.id)] ?? null
              }
              onOpenReplay={() => {
                const reel =
                  tradeReelsByTradeId[String(selectedTradeDetail.id)]
                if (reel) openReelDetail(reel)
              }}
              onStartEditTrade={() => {
                openEditTradeModal(selectedTradeDetail)
                setSelectedTradeDetail(null)
              }}
              onTogglePinTrade={() => void handlePinTrade(selectedTradeDetail)}
              onDeleteTrade={() =>
                void handleDeleteTrade(String(selectedTradeDetail.id))
              }
              showInteractions={true}
              commentsExpanded
              scrollToCommentsOnMount={tradeDetailFocusComments}
              disableOpen
              onImageClick={setScreenshotLightboxUrl}
            />
          </div>
        </DetailModalShell>
      ) : null}

      {selectedReelDetail ? (
        <FeedReelDetailModal
          post={selectedReelDetail}
          user={currentUserId ? { id: currentUserId } : null}
          comments={commentsByPost[String(selectedReelDetail.id)] || []}
          likeMeta={
            likesByPost[String(selectedReelDetail.id)] || EMPTY_LIKE_META
          }
          likeBusy={!!likeBusyByPost[String(selectedReelDetail.id)]}
          commentSubmitting={
            !!commentSubmitting[String(selectedReelDetail.id)]
          }
          draftSyncRef={feedDraftSyncRef}
          openCommentsRef={feedOpenCommentsRef}
          onClose={() => setSelectedReelDetail(null)}
          onToggleLike={(post) => void handleReelLike(String(post.id))}
          onSubmitComment={submitReelComment}
          onDeleteComment={deleteComment}
          onTogglePinComment={togglePinComment}
          onSharePost={(post) => setSharePost(post)}
          canManageReel={currentUserId === profile?.id}
          menuOpen={openMenuId === String(selectedReelDetail.id)}
          onMenuToggle={() =>
            setOpenMenuId((prev) =>
              prev === String(selectedReelDetail.id)
                ? null
                : String(selectedReelDetail.id)
            )
          }
          onEditReel={() => handleStartEditReel(selectedReelDetail)}
          onDeleteReel={() => requestDeleteReel(selectedReelDetail)}
          onReplaceReelVideo={() => handleReplaceReelVideo(selectedReelDetail)}
          isTradeAttachedReel={isTradeAttachedReel(selectedReelDetail)}
          stacked={selectedTradeDetail != null}
        />
      ) : null}

      {selectedPostDetail ? (
        <DetailModalShell
          ariaLabel="Post details"
          title="Post"
          layout="split"
          backdropClassName="bg-black/75 backdrop-blur-md"
          onClose={() => {
            setSelectedPostDetail(null)
            setPostDetailFocusComments(false)
            setScreenshotLightboxUrl(null)
          }}
        >
          <PostCard
            inDetailModal
            post={selectedPostDetail}
            profile={profile}
            canManagePost={currentUserId === profile.id}
            menuOpen={openMenuId === String(selectedPostDetail.id)}
            onMenuToggle={() =>
              setOpenMenuId((prev) =>
                prev === String(selectedPostDetail.id)
                  ? null
                  : String(selectedPostDetail.id)
              )
            }
            onStartEditPost={() => {
              setEditingPost(selectedPostDetail)
              setEditContent(selectedPostDetail.content || "")
              setOpenMenuId(null)
              setSelectedPostDetail(null)
            }}
            onTogglePinPost={() => void handlePinPost(selectedPostDetail)}
            onSavePost={() => void handleSavePost(String(selectedPostDetail.id))}
            onDeletePost={() => void handleDeletePost(String(selectedPostDetail.id))}
            showInteractions={true}
            onLike={() => void handleLike(String(selectedPostDetail.id), "post")}
            likeBusy={!!likeBusyByPost[String(selectedPostDetail.id)]}
            showCommentsPanel
            scrollToCommentsOnMount={postDetailFocusComments}
            likeMeta={likesByPost[String(selectedPostDetail.id)] || { count: 0, liked: false }}
            comments={commentsByPost[String(selectedPostDetail.id)] || []}
            commentText={commentDraft[String(selectedPostDetail.id)] || ""}
            onCommentChange={(value) =>
              setCommentDraft((prev) => ({
                ...prev,
                [String(selectedPostDetail.id)]: value,
              }))
            }
            onCommentSubmit={(parentCommentId) =>
              void submitComment(String(selectedPostDetail.id), "post", parentCommentId)
            }
            commentSubmitting={!!commentSubmitting[String(selectedPostDetail.id)]}
            currentUserId={currentUserId}
            onDeleteComment={deleteComment}
            onTogglePinComment={togglePinComment}
            disableOpen
            onImageClick={setScreenshotLightboxUrl}
            onSharePost={currentUserId ? handleSharePost : undefined}
          />
        </DetailModalShell>
      ) : null}

      {feedDeepLinkPost ? (
        <FeedPostDetailModal
          post={feedDeepLinkPost}
          user={currentUserId ? { id: currentUserId } : null}
          comments={feedDeepLinkComments}
          likeMeta={feedDeepLinkLikeMeta}
          commentSubmitting={feedDeepLinkCommentSubmitting}
          draftSyncRef={feedDraftSyncRef}
          openCommentsRef={feedOpenCommentsRef}
          onClose={() => setFeedDeepLinkPost(null)}
          onToggleLike={toggleFeedDeepLinkLike}
          onSubmitComment={submitFeedDeepLinkComment}
          onDeleteComment={deleteComment}
          onTogglePinComment={togglePinComment}
          onSharePost={currentUserId ? handleSharePost : undefined}
        />
      ) : null}

      <ImageLightbox
        imageUrl={screenshotLightboxUrl}
        onClose={() => setScreenshotLightboxUrl(null)}
      />

      {selectedAchievementPostDetail ? (
        <FeedProfilePostDetailModal
          post={selectedAchievementPostDetail}
          user={currentUserId ? { id: currentUserId } : null}
          comments={
            commentsByPost[String(selectedAchievementPostDetail.id)] || []
          }
          likeMeta={
            likesByPost[String(selectedAchievementPostDetail.id)] ||
            EMPTY_LIKE_META
          }
          likeBusy={
            !!likeBusyByPost[String(selectedAchievementPostDetail.id)]
          }
          commentSubmitting={
            !!commentSubmitting[String(selectedAchievementPostDetail.id)]
          }
          draftSyncRef={feedDraftSyncRef}
          openCommentsRef={feedOpenCommentsRef}
          onClose={() => {
            setSelectedAchievementPostDetail(null)
          }}
          onToggleLike={(post) => void handleAchievementLike(String(post.id))}
          onSubmitComment={submitAchievementPostComment}
          onDeleteComment={deleteComment}
          onTogglePinComment={togglePinComment}
          onSharePost={(post) => {
            const achievement = post.achievements as Achievement | undefined
            if (achievement) {
              handleShareAchievement(achievement, String(post.id))
            }
          }}
        />
      ) : null}

      {sharePost ? (
        <ShareToConversationsModal
          open
          onClose={() => setSharePost(null)}
          title="Send Post"
          postId={String(sharePost.id)}
          feedKind={
            sharePost.feedKind === "achievement"
              ? "achievement"
              : sharePost.feedKind === "profile"
                ? "profile"
                : sharePost.feedKind === "reel"
                  ? "reel"
                  : "trade"
          }
          post={sharePost}
          captionPlaceholder="Add a message..."
          showCancel={false}
        />
      ) : null}

      {editingPost ? (
        <div
          className="fixed inset-0 z-[200] flex items-center justify-center bg-black/70 p-4 backdrop-blur-md"
          role="presentation"
          onClick={() => setEditingPost(null)}
        >
          <div
            className="w-full max-w-[400px] rounded-xl border border-white/10 bg-[#0f172a] p-6"
            role="dialog"
            aria-modal="true"
            aria-labelledby="edit-post-title"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="mb-3 flex items-center justify-between">
              <h2 id="edit-post-title" className="text-lg font-semibold text-white">
                Edit Post
              </h2>
              <button
                type="button"
                onClick={() => setEditingPost(null)}
                className="rounded p-1.5 text-gray-400 hover:bg-white/10 hover:text-white"
              >
                ✕
              </button>
            </div>
            <textarea
              value={editContent}
              onChange={(e) => setEditContent(e.target.value)}
              className="mb-3 w-full rounded border border-white/10 bg-[#020617] p-2 text-sm text-white"
              rows={4}
            />
            <button
              type="button"
              onClick={() => void handleUpdatePost()}
              className="w-full rounded bg-blue-500 px-4 py-2 text-sm font-medium text-white hover:bg-blue-600"
            >
              Save Changes
            </button>
          </div>
        </div>
      ) : null}

      {editingTrade ? (
        <InputTradeForm
          key={String(editingTrade.id)}
          existingTrade={editingTrade}
          onClose={() => setEditingTrade(null)}
          onSave={() => {
            if (profile?.id) {
              setVisibleTradeCount(PAGE_SIZE)
              void fetchTradesForProfile(profile.id, 0).then((page) => {
                setAllTrades(page.rows)
                setTradeHasMore(page.hasMore)
                setTradesReady(true)
              })
            }
            setEditingTrade(null)
          }}
        />
      ) : null}

      <FollowListModal
        open={showFollowers}
        onClose={closeFollowModals}
        profileId={profile?.id ?? ""}
        kind="followers"
        isOwnProfile={isOwnProfile}
      />
      <FollowListModal
        open={showFollowing}
        onClose={closeFollowModals}
        profileId={profile?.id ?? ""}
        kind="following"
        isOwnProfile={isOwnProfile}
      />

      <ImageCropModal
        open={postImageCrop.cropSourceFile != null}
        file={postImageCrop.cropSourceFile}
        preset="content"
        onCancel={postImageCrop.handleCropCancel}
        onSave={postImageCrop.handleCropSave}
      />
    </>
  )
}

export default function ProfilePage() {
  return (
    <Suspense
      fallback={
        <>
          <SkeletonProfilePage />
        </>
      }
    >
      <ProfilePageContent />
    </Suspense>
  )
}
