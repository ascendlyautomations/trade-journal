"use client"

import type { ChangeEvent } from "react"
import Link from "next/link"
import dynamic from "next/dynamic"
import { Suspense, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react"
import { usePathname, useRouter, useSearchParams } from "next/navigation"
import { supabase } from "../../../lib/supabaseClient"
import { feedbackPresets } from "@/lib/feedbackPresets"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import {
  deleteFeedComment,
  deleteProfilePostComment,
  deleteAchievementPostComment,
  deleteReelComment,
  filterCommentsAfterDelete,
} from "@/lib/deleteComment"
import {
  applyPinnedCommentState,
  canPinComment,
  pinCommentByKind,
  resolveCommentPinTarget,
} from "@/lib/pinComment"
import { ensureCommentNotificationsForInsert } from "@/lib/commentNotifications"
import {
  ACHIEVEMENT_POST_COMMENT_INSERT_SELECT,
  FEED_ACHIEVEMENT_POSTS_SELECT,
  achievementPostOwnerUserId,
  insertAchievementPostCommentNotifications,
  isAchievementFeedPost,
  queryAchievementPostComments,
  withInsertedAchievementPostParentCommentId,
} from "@/lib/achievementPostEngagement"
import {
  PROFILE_POST_COMMENT_INSERT_SELECT,
  insertProfilePostCommentNotifications,
  isProfileFeedPost,
  profilePostOwnerUserId,
  queryProfilePostComments,
  withInsertedProfilePostParentCommentId,
} from "@/lib/profilePostEngagement"
import FeedLoadMoreFooter from "../../components/feed/FeedLoadMoreFooter"
import NativeIosPullToRefresh from "@/app/components/NativeIosPullToRefresh"
import FeedContentToggle from "../../components/feed/FeedContentToggle"
import FeedModeToggle from "../../components/feed/FeedModeToggle"
import FeedPostList from "../../components/feed/FeedPostList"
import FeedStoriesBar from "../../components/feed/FeedStoriesBar"
import {
  EMPTY_COMMENTS,
  EMPTY_LIKE_META,
} from "../../components/feed/FeedPostCard"
import {
  FEED_COMMENT_INSERT_SELECT,
  FEED_POSTS_SELECT,
  buildFeedPostsIndex,
  normalizeAchievementFeedItem,
  normalizeProfileFeedItem,
  normalizeReelFeedItem,
  normalizeTradeFeedItem,
  postAttachedReel,
  postTradeOwnerUserId,
  feedContentOwnerUserId,
  queryFeedComments,
  reelDetailFeedItem,
  withInsertedParentCommentId,
  type FeedContentFilter,
  type FeedItem,
} from "../../components/feed/feedPostHelpers"
import {
  type ActiveStoryRow,
  type StoryBarProfile,
  userHasActiveStory,
} from "@/lib/activeStories"
import { useActiveStories } from "@/lib/useActiveStories"
import {
  FEED_PAGE_SIZE,
  FEED_PROFILE_POSTS_SELECT,
  fetchFollowingIds,
  fetchProfileFeedBatch,
  fetchTradeFeedBatch,
  fetchAchievementFeedBatch,
  fetchReelFeedBatch,
  topUpMergedFeedBuffer,
} from "@/lib/feedContent"
import {
  readFeedSession,
  writeFeedSession,
  patchFeedReelInSessionsForUser,
  removeFeedReelFromSessionsForUser,
  type FeedSessionSnapshot,
} from "@/lib/feedSessionCache"
import { readExploreSession } from "@/lib/exploreSessionCache"
import { useDeleteReelConfirmation, useFeedbackPopup } from "@/app/components/ui"
import { useModalScrollLock } from "@/app/components/ui/modalLayout"
import EmptyState from "@/app/components/ui/EmptyState"
import { SkeletonFeedPage } from "@/app/components/ui/skeletons"
import { publishStory } from "@/lib/publishStory"
import { useUploadProgress } from "@/lib/uploadProgress/UploadProgressProvider"
import {
  createStoryPreviewUrl,
  prepareStoryImageFile,
  revokeStoryPreviewUrl,
} from "@/lib/storyComposeHelpers"
import {
  REEL_COMMENT_INSERT_SELECT,
  FEED_REELS_SELECT,
  fetchReelLikeMetaByIds,
  insertReelCommentNotifications,
  isReelFeedPost,
  queryReelComments,
  reelOwnerUserId,
  toggleReelLike,
  withInsertedReelParentCommentId,
} from "@/lib/reelEngagement"
import { toggleContentLike } from "@/lib/toggleContentLike"
import { createOptimisticTempId } from "@/lib/optimisticMutation"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { deleteReel, isTradeAttachedReel, replaceTradeReelVideo, type ReelRow } from "@/lib/reels"
import {
  feedDeepLinkSessionKey,
  fetchFeedDeepLinkContent,
  parseFeedDeepLinkTarget,
} from "@/lib/feedDeepLink"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { isDemoUserId } from "@/lib/demo/constants"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import {
  getDemoStoryBarProfiles,
  loadDemoFeedEngagement,
} from "@/lib/demo/demoFeed"
import type { DemoSignupReason } from "@/lib/demo/DemoModeContext"

const FeedPostOverlays = dynamic(
  () => import("../../components/feed/FeedPostOverlays")
)
const FeedStoryViewer = dynamic(
  () => import("../../components/feed/FeedStoryViewer")
)
const StoryComposeModal = dynamic(
  () => import("../../components/feed/StoryComposeModal")
)
const ReelComposerModal = dynamic(
  () => import("@/app/components/profile/ReelComposerModal")
)
const FeedbackModal = dynamic(
  () => import("@/app/components/ui/FeedbackModal")
)
const ConfirmModal = dynamic(
  () => import("@/app/components/ui/ConfirmModal")
)

/** Auto-advance each slide (Instagram-style). */
const STORY_SLIDE_MS = 7000
const EMPTY_STORY_LIST: ActiveStoryRow[] = []

type LikeMeta = { count: number; liked: boolean }

type FeedEmptyState = "following_nobody" | "no_posts"

function guardDemoFeedWrite(reason: DemoSignupReason): boolean {
  if (!isDemoModeActive()) return false
  requestDemoSignup(reason)
  return true
}

export default function FeedPage() {
  return (
    <Suspense fallback={<SkeletonFeedPage />}>
      <FeedPageContent />
    </Suspense>
  )
}

function FeedPageContent() {
  const searchParams = useSearchParams()
  const router = useRouter()
  const pathname = usePathname()
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const { user, profile, loading: profileLoading } = useUserProfile()
  const authChecked = !!user?.id
  const [posts, setPosts] = useState<any[]>([])
  const [page, setPage] = useState(0)
  const [loading, setLoading] = useState(false)
  const [hasMore, setHasMore] = useState(true)
  const pageRef = useRef(0)
  const loadingRef = useRef(false)
  const hasMoreRef = useRef(true)
  const [mode, setMode] = useState<"global" | "following">("global")
  const [feedDefaultModeReady, setFeedDefaultModeReady] = useState(false)
  const userPickedModeRef = useRef(false)
  const defaultModeResolvedRef = useRef(false)
  const defaultModeUserIdRef = useRef<string | null>(null)
  const [contentType, setContentType] = useState<FeedContentFilter>("all")
  const mergeBufferRef = useRef<FeedItem[]>([])
  const tradePageRef = useRef(0)
  const profilePageRef = useRef(0)
  const achievementPageRef = useRef(0)
  const reelPageRef = useRef(0)
  const tradeExhaustedRef = useRef(false)
  const profileExhaustedRef = useRef(false)
  const achievementExhaustedRef = useRef(false)
  const reelExhaustedRef = useRef(false)
  const userIdRef = useRef<string | null>(null)
  userIdRef.current = user?.id ?? null
  const profileRef = useRef(profile)
  profileRef.current = profile
  const feedInitKeyRef = useRef<string | null>(null)
  const hasLoadedFeedRef = useRef(false)
  const followingIdsRef = useRef<string[]>([])
  const [likesByPost, setLikesByPost] = useState<Record<string, LikeMeta>>({})
  const [commentCountsByPost, setCommentCountsByPost] = useState<
    Record<string, number>
  >({})
  const [commentsByPost, setCommentsByPost] = useState<Record<string, any[]>>({})
  const postsRef = useRef<any[]>([])
  postsRef.current = posts
  const likesByPostRef = useRef(likesByPost)
  likesByPostRef.current = likesByPost
  const commentCountsByPostRef = useRef(commentCountsByPost)
  commentCountsByPostRef.current = commentCountsByPost
  const commentsByPostRef = useRef(commentsByPost)
  commentsByPostRef.current = commentsByPost
  const commentsLoadedRef = useRef<Set<string>>(new Set())
  const commentsLoadingRef = useRef<Map<string, Promise<any[]>>>(new Map())
  const [commentSubmitting, setCommentSubmitting] = useState<Record<string, boolean>>({})
  const [selectedPostId, setSelectedPostId] = useState<string | null>(null)
  const [tradeExpandSignal, setTradeExpandSignal] = useState(0)
  /** Modal-owned post data for URL deep links — independent of the feed array. */
  const [feedModalPost, setFeedModalPost] = useState<FeedItem | null>(null)
  /** Clip opened from Trade Details — stacked above the trade modal without closing it. */
  const [stackedAttachedReel, setStackedAttachedReel] = useState<FeedItem | null>(
    null
  )
  const [sharePostId, setSharePostId] = useState<string | null>(null)
  const [openReelMenuId, setOpenReelMenuId] = useState<string | null>(null)
  const [editingReel, setEditingReel] = useState<ReelRow | null>(null)
  const replaceReelInputRef = useRef<HTMLInputElement>(null)
  const [replacingReelPost, setReplacingReelPost] = useState<any | null>(null)
  const [followingStoryUserIds, setFollowingStoryUserIds] = useState<string[]>(
    []
  )
  const [users, setUsers] = useState<StoryBarProfile[]>([])
  const [currentUserProfile, setCurrentUserProfile] =
    useState<StoryBarProfile | null>(null)
  const [activeStoryUser, setActiveStoryUser] = useState<string | null>(null)
  const [currentStoryIndex, setCurrentStoryIndex] = useState(0)
  const [storyComposeOpen, setStoryComposeOpen] = useState(false)
  const [pendingStoryFile, setPendingStoryFile] = useState<File | null>(null)
  const [pendingStoryPreviewUrl, setPendingStoryPreviewUrl] = useState<
    string | null
  >(null)
  const [postingStory, setPostingStory] = useState(false)
  const [feedEmptyState, setFeedEmptyState] = useState<FeedEmptyState | null>(
    null
  )
  const [feedLoadError, setFeedLoadError] = useState<string | null>(null)
  const feedEmptyStateRef = useRef<FeedEmptyState | null>(null)
  feedEmptyStateRef.current = feedEmptyState
  const scrollYRef = useRef(0)
  /** Incremented on tab/filter change; stale async work must not mutate state. */
  const feedRequestGenerationRef = useRef(0)
  const [feedReady, setFeedReady] = useState(false)

  const bumpFeedRequestGeneration = useCallback(() => {
    feedRequestGenerationRef.current += 1
    return feedRequestGenerationRef.current
  }, [])

  const handleFeedModeChange = useCallback((next: "global" | "following") => {
    userPickedModeRef.current = true
    defaultModeResolvedRef.current = true
    setMode(next)
  }, [])

  useLayoutEffect(() => {
    if (!user?.id) {
      setFeedDefaultModeReady(false)
      defaultModeUserIdRef.current = null
      return
    }

    if (defaultModeUserIdRef.current !== user.id) {
      defaultModeUserIdRef.current = user.id
      defaultModeResolvedRef.current = false
      userPickedModeRef.current = false
      setMode("global")
    }

    if (userPickedModeRef.current) {
      defaultModeResolvedRef.current = true
      setFeedDefaultModeReady(true)
      return
    }

    if (!defaultModeResolvedRef.current) {
      const explore = readExploreSession()
      if (explore?.currentUserId === user.id) {
        followingIdsRef.current = explore.followingIds
        if (explore.followingIds.length > 0) {
          setMode("following")
        }
        defaultModeResolvedRef.current = true
      }
    }

    setFeedDefaultModeReady(true)
  }, [user?.id])

  const buildFeedSnapshot = useCallback(
    (
      nextPosts: any[],
      nextLikes: Record<string, LikeMeta>,
      nextComments: Record<string, any[]>,
      overrides?: Partial<FeedSessionSnapshot>
    ): FeedSessionSnapshot => ({
      posts: nextPosts,
      likesByPost: nextLikes,
      commentCountsByPost: { ...commentCountsByPostRef.current },
      commentsByPost: nextComments,
      page: pageRef.current,
      hasMore: hasMoreRef.current,
      feedEmptyState: feedEmptyStateRef.current,
      mergeBuffer: [...mergeBufferRef.current],
      tradePage: tradePageRef.current,
      profilePage: profilePageRef.current,
      achievementPage: achievementPageRef.current,
      reelPage: reelPageRef.current,
      tradeExhausted: tradeExhaustedRef.current,
      profileExhausted: profileExhaustedRef.current,
      achievementExhausted: achievementExhaustedRef.current,
      reelExhausted: reelExhaustedRef.current,
      hasLoaded: hasLoadedFeedRef.current,
      scrollY: scrollYRef.current,
      ...overrides,
    }),
    []
  )

  const persistFeedSnapshot = useCallback(
    (
      nextPosts: any[],
      nextLikes: Record<string, LikeMeta>,
      nextComments: Record<string, any[]>,
      overrides?: Partial<FeedSessionSnapshot>,
      requestGeneration?: number
    ) => {
      if (
        requestGeneration != null &&
        requestGeneration !== feedRequestGenerationRef.current
      ) {
        return
      }
      const key = feedInitKeyRef.current
      if (!key) return
      writeFeedSession(
        key,
        buildFeedSnapshot(nextPosts, nextLikes, nextComments, overrides)
      )
    },
    [buildFeedSnapshot]
  )

  const clearFeedDeepLinkParams = useCallback(() => {
    const params = new URLSearchParams(searchParams.toString())
    params.delete("post")
    params.delete("trade")
    params.delete("achievement")
    params.delete("reel")
    params.delete("comments")
    const qs = params.toString()
    router.replace(qs ? `${pathname}?${qs}` : pathname, { scroll: false })
  }, [pathname, router, searchParams])

  const draftSyncRef = useRef<Record<string, string>>({})
  const openCommentsRef = useRef<Record<string, boolean>>({})
  const openTradeRef = useRef<Record<string, boolean>>({})
  const feedDeepLinkHandledRef = useRef<string | null>(null)
  const likeBusyRef = useRef<Set<string>>(new Set())
  const commentSubmittingRef = useRef<Set<string>>(new Set())
  const postingStoryRef = useRef(false)
  const uploadingStoryRef = useRef(false)
  const { runUpload } = useUploadProgress()
  const [likeBusyByPost, setLikeBusyByPost] = useState<Record<string, boolean>>({})

  const {
    storiesByUser,
    loadStories: reloadActiveStories,
  } = useActiveStories(
    followingStoryUserIds,
    !!user?.id &&
      mode === "following" &&
      followingStoryUserIds.length > 0
  )

  const currentStories = useMemo(
    () =>
      activeStoryUser
        ? storiesByUser[activeStoryUser] ?? EMPTY_STORY_LIST
        : EMPTY_STORY_LIST,
    [activeStoryUser, storiesByUser]
  )
  const currentStory = useMemo(
    () => currentStories[currentStoryIndex] ?? null,
    [currentStories, currentStoryIndex]
  )

  const currentUserHasStory = useMemo(
    () => userHasActiveStory(storiesByUser, user?.id),
    [user?.id, storiesByUser]
  )

  useEffect(() => {
    if (!user?.id || mode !== "following") {
      if (mode !== "following") {
        setFollowingStoryUserIds([])
      }
      return
    }

    if (followingIdsRef.current.length > 0) {
      setFollowingStoryUserIds([
        ...new Set([...followingIdsRef.current, user.id]),
      ])
    }
  }, [user?.id, mode])

  useEffect(() => {
    if (!user?.id) {
      setCurrentUserProfile(null)
      setUsers([])
      return
    }

    setCurrentUserProfile(
      profile
        ? {
            id: profile.id,
            username: profile.username,
            avatar_url: profile.avatar_url,
          }
        : { id: user.id, username: null, avatar_url: null }
    )

    const userIdsWithStories = Object.keys(storiesByUser)
    if (userIdsWithStories.length === 0) {
      setUsers([])
      return
    }

    let cancelled = false

    void (async () => {
      if (isDemoModeActive()) {
        if (cancelled) return
        const list = getDemoStoryBarProfiles(userIdsWithStories)
        const latestStoryMs = (id: string) =>
          new Date(storiesByUser[id][0].created_at).getTime()
        list.sort((a, b) => latestStoryMs(b.id) - latestStoryMs(a.id))
        setUsers(list)
        return
      }

      const { data: profiles, error } = await supabase
        .from("profiles")
        .select("id, username, avatar_url")
        .in("id", userIdsWithStories)

      if (cancelled) return

      if (error) {
        console.error("[feed] story bar profiles:", error)
        setUsers([])
        return
      }

      const latestStoryMs = (id: string) =>
        new Date(storiesByUser[id][0].created_at).getTime()

      const list = [...(profiles ?? [])] as StoryBarProfile[]
      list.sort((a, b) => latestStoryMs(b.id) - latestStoryMs(a.id))
      setUsers(list)
    })()

    return () => {
      cancelled = true
    }
  }, [profile, storiesByUser, user?.id])

  const storyNavigation = useMemo(() => {
    const list = activeStoryUser
      ? (storiesByUser[activeStoryUser] ?? [])
      : []
    const userIds = users.map((u) => u.id)
    const currentUserIndex = activeStoryUser
      ? userIds.indexOf(activeStoryUser)
      : -1

    return {
      canGoPrevSlide: currentStoryIndex > 0,
      canGoNextSlide: currentStoryIndex < list.length - 1,
      canGoPrevUser: currentUserIndex > 0,
      canGoNextUser:
        currentUserIndex >= 0 && currentUserIndex < userIds.length - 1,
    }
  }, [activeStoryUser, currentStoryIndex, storiesByUser, users])

  useEffect(() => {
    return () => {
      revokeStoryPreviewUrl(pendingStoryPreviewUrl)
    }
  }, [pendingStoryPreviewUrl])

  const closeStoryCompose = useCallback(() => {
    revokeStoryPreviewUrl(pendingStoryPreviewUrl)
    setPendingStoryPreviewUrl(null)
    setPendingStoryFile(null)
    setStoryComposeOpen(false)
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
      if (!file || !user?.id) return
      await setStoryDraft(file)
    },
    [setStoryDraft, user?.id]
  )

  useEffect(() => {
    if (!user?.id || mode !== "following") {
      setFollowingStoryUserIds([])
      setUsers([])
      setCurrentUserProfile(null)
      setActiveStoryUser(null)
      setCurrentStoryIndex(0)
    }
  }, [user?.id, mode])

  const handlePostStory = useCallback(async () => {
    if (guardDemoFeedWrite("upload")) return
    if (
      !pendingStoryFile ||
      !user?.id ||
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

          const result = await publishStory(supabase, user.id, storyFile, {
            onProgress: report,
          })

          if (!result.ok) {
            throw new Error(result.message)
          }

          showPopup({ type: "success", message: "Story uploaded!" })
          await reloadActiveStories()
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
    user?.id,
    postingStory,
    showPopup,
    closeStoryCompose,
    reloadActiveStories,
    runUpload,
  ])

  const openStory = useCallback((userId: string) => {
    setActiveStoryUser(userId)
    setCurrentStoryIndex(0)
  }, [])

  const handleCloseStoryViewer = useCallback(() => {
    setActiveStoryUser(null)
    setCurrentStoryIndex(0)
  }, [])

  const nextSlide = useCallback(() => {
    const list = activeStoryUser
      ? (storiesByUser[activeStoryUser] ?? [])
      : []

    if (currentStoryIndex < list.length - 1) {
      setCurrentStoryIndex((prev) => prev + 1)
    }
  }, [activeStoryUser, currentStoryIndex, storiesByUser])

  const prevSlide = useCallback(() => {
    if (currentStoryIndex > 0) {
      setCurrentStoryIndex((prev) => prev - 1)
    }
  }, [currentStoryIndex])

  const nextUser = useCallback(() => {
    const userIds = users.map((u) => u.id)
    const currentUserIndex = activeStoryUser
      ? userIds.indexOf(activeStoryUser)
      : -1

    if (currentUserIndex >= 0 && currentUserIndex < userIds.length - 1) {
      setActiveStoryUser(userIds[currentUserIndex + 1])
      setCurrentStoryIndex(0)
    }
  }, [activeStoryUser, users])

  const prevUser = useCallback(() => {
    const userIds = users.map((u) => u.id)
    const currentUserIndex = activeStoryUser
      ? userIds.indexOf(activeStoryUser)
      : -1

    if (currentUserIndex > 0) {
      const prevUserId = userIds[currentUserIndex - 1]
      const prevUserStories = storiesByUser[prevUserId] ?? []
      setActiveStoryUser(prevUserId)
      setCurrentStoryIndex(Math.max(0, prevUserStories.length - 1))
    }
  }, [activeStoryUser, storiesByUser, users])

  const nextStory = useCallback(() => {
    const list = activeStoryUser
      ? (storiesByUser[activeStoryUser] ?? [])
      : []

    if (currentStoryIndex < list.length - 1) {
      setCurrentStoryIndex((prev) => prev + 1)
      return
    }

    nextUser()
  }, [activeStoryUser, currentStoryIndex, storiesByUser, nextUser])

  const prevStory = useCallback(() => {
    if (currentStoryIndex > 0) {
      setCurrentStoryIndex((prev) => prev - 1)
      return
    }

    prevUser()
  }, [currentStoryIndex, prevUser])

  useEffect(() => {
    if (!activeStoryUser) return
    const list = storiesByUser[activeStoryUser] ?? []
    if (list.length === 0) {
      setActiveStoryUser(null)
      setCurrentStoryIndex(0)
      return
    }
    if (currentStoryIndex >= list.length) {
      setCurrentStoryIndex(Math.max(0, list.length - 1))
    }
  }, [activeStoryUser, storiesByUser, currentStoryIndex])

  useEffect(() => {
    if (!activeStoryUser) return
    const list = storiesByUser[activeStoryUser] ?? []
    if (list.length === 0) return
    if (currentStoryIndex >= list.length - 1) return

    const timer = window.setTimeout(() => {
      nextSlide()
    }, STORY_SLIDE_MS)

    return () => clearTimeout(timer)
  }, [activeStoryUser, currentStoryIndex, storiesByUser, nextSlide])

  useEffect(() => {
    if (!activeStoryUser) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") {
        setActiveStoryUser(null)
        setCurrentStoryIndex(0)
        return
      }
      if (e.key === "ArrowLeft") {
        e.preventDefault()
        prevStory()
      }
      if (e.key === "ArrowRight") {
        e.preventDefault()
        nextStory()
      }
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [activeStoryUser, nextStory, prevStory])

  const feedOverlayOpen = Boolean(selectedPostId || activeStoryUser)
  useModalScrollLock(feedOverlayOpen)

  const loadEngagementForPosts = useCallback(async (postList: any[], currentUser: any) => {
    if (!postList.length) {
      return {
        enriched: [] as any[],
        likesMap: {} as Record<string, LikeMeta>,
        commentCountsMap: {} as Record<string, number>,
      }
    }

    if (isDemoUserId(currentUser?.id)) {
      const demo = await loadDemoFeedEngagement(postList, currentUser)
      return {
        enriched: demo.enriched,
        likesMap: demo.likesMap,
        commentCountsMap: Object.fromEntries(
          Object.entries(demo.commentsMap).map(([id, comments]) => [
            id,
            comments.length,
          ])
        ),
      }
    }

    const tradeIds = postList
      .filter(
        (p) =>
          !isProfileFeedPost(p) &&
          !isAchievementFeedPost(p) &&
          !isReelFeedPost(p)
      )
      .map((p) => p.id)
    const profileIds = postList
      .filter((p) => isProfileFeedPost(p))
      .map((p) => p.id)
    const achievementIds = postList
      .filter((p) => isAchievementFeedPost(p))
      .map((p) => p.id)
    const reelIds = [
      ...postList.filter((p) => isReelFeedPost(p)).map((p) => String(p.id)),
      ...postList
        .filter(
          (p) =>
            !isProfileFeedPost(p) &&
            !isAchievementFeedPost(p) &&
            !isReelFeedPost(p)
        )
        .map((p) => postAttachedReel(p)?.id)
        .filter((id): id is string => id != null && String(id).trim() !== "")
        .map(String),
    ].filter((id, index, arr) => arr.indexOf(id) === index)

    const [
      { data: tradeLikesRows },
      { data: tradeCommentsRows },
      { data: profileLikesRows },
      { data: profileCommentsRows },
      { data: achievementLikesRows },
      { data: achievementCommentsRows },
      { data: reelLikesRows },
      { data: reelCommentsRows },
    ] = await Promise.all([
      tradeIds.length
        ? supabase.from("likes").select("post_id, user_id").in("post_id", tradeIds)
        : Promise.resolve({ data: [] as { post_id: string; user_id: string }[] }),
      tradeIds.length
        ? supabase.from("comments").select("post_id").in("post_id", tradeIds)
        : Promise.resolve({ data: [] as any[] }),
      profileIds.length
        ? supabase
            .from("profile_post_likes")
            .select("profile_post_id, user_id")
            .in("profile_post_id", profileIds)
        : Promise.resolve({ data: [] as { profile_post_id: string; user_id: string }[] }),
      profileIds.length
        ? supabase
            .from("profile_post_comments")
            .select("profile_post_id")
            .in("profile_post_id", profileIds)
        : Promise.resolve({ data: [] as any[] }),
      achievementIds.length
        ? supabase
            .from("achievement_post_likes")
            .select("achievement_post_id, user_id")
            .in("achievement_post_id", achievementIds)
        : Promise.resolve({
            data: [] as { achievement_post_id: string; user_id: string }[],
          }),
      achievementIds.length
        ? supabase
            .from("achievement_post_comments")
            .select("achievement_post_id")
            .in("achievement_post_id", achievementIds)
        : Promise.resolve({ data: [] as any[] }),
      reelIds.length
        ? supabase
            .from("reel_likes")
            .select("reel_id, user_id")
            .in("reel_id", reelIds)
        : Promise.resolve({
            data: [] as { reel_id: string; user_id: string }[],
          }),
      reelIds.length
        ? supabase
            .from("reel_comments")
            .select("reel_id")
            .in("reel_id", reelIds)
        : Promise.resolve({ data: [] as any[] }),
    ])

    const likesMap: Record<string, LikeMeta> = {}
    const commentCountsMap: Record<string, number> = {}
    for (const p of postList) {
      const key = String(p.id)
      likesMap[key] = { count: 0, liked: false }
      commentCountsMap[key] = 0
    }

    for (const row of tradeLikesRows || []) {
      const pid = String(row.post_id)
      if (!likesMap[pid]) likesMap[pid] = { count: 0, liked: false }
      likesMap[pid].count++
      if (currentUser && row.user_id === currentUser.id) likesMap[pid].liked = true
    }
    for (const row of profileLikesRows || []) {
      const pid = String(row.profile_post_id)
      if (!likesMap[pid]) likesMap[pid] = { count: 0, liked: false }
      likesMap[pid].count++
      if (currentUser && row.user_id === currentUser.id) likesMap[pid].liked = true
    }
    for (const row of achievementLikesRows || []) {
      const pid = String(row.achievement_post_id)
      if (!likesMap[pid]) likesMap[pid] = { count: 0, liked: false }
      likesMap[pid].count++
      if (currentUser && row.user_id === currentUser.id) likesMap[pid].liked = true
    }
    for (const row of reelLikesRows || []) {
      const pid = String(row.reel_id)
      if (!likesMap[pid]) likesMap[pid] = { count: 0, liked: false }
      likesMap[pid].count++
      if (currentUser && row.user_id === currentUser.id) likesMap[pid].liked = true
    }

    for (const c of tradeCommentsRows || []) {
      const pid = String(c.post_id)
      commentCountsMap[pid] = (commentCountsMap[pid] ?? 0) + 1
    }
    for (const c of profileCommentsRows || []) {
      const pid = String(c.profile_post_id)
      commentCountsMap[pid] = (commentCountsMap[pid] ?? 0) + 1
    }
    for (const c of achievementCommentsRows || []) {
      const pid = String(c.achievement_post_id)
      commentCountsMap[pid] = (commentCountsMap[pid] ?? 0) + 1
    }
    for (const c of reelCommentsRows || []) {
      const pid = String(c.reel_id)
      commentCountsMap[pid] = (commentCountsMap[pid] ?? 0) + 1
    }

    const enriched = postList.map((p) => {
      const key = String(p.id)
      return {
        ...p,
        likesCount: likesMap[key]?.count ?? 0,
      }
    })
    return { enriched, likesMap, commentCountsMap }
  }, [])

  const loadCommentsForPost = useCallback(
    (post: any): Promise<any[]> => {
      const pid = String(post.id)
      if (commentsLoadedRef.current.has(pid)) {
        return Promise.resolve(commentsByPostRef.current[pid] ?? EMPTY_COMMENTS)
      }

      const pending = commentsLoadingRef.current.get(pid)
      if (pending) return pending

      const request = (async () => {
        try {
          let comments: any[] = []

          if (isDemoUserId(userIdRef.current)) {
            const demoUserId = userIdRef.current
            if (!demoUserId) return EMPTY_COMMENTS
            const demo = await loadDemoFeedEngagement(
              [post],
              { id: demoUserId }
            )
            comments = demo.commentsMap[pid] ?? []
          } else if (isProfileFeedPost(post)) {
            const result = await queryProfilePostComments(async (select) =>
              supabase
                .from("profile_post_comments")
                .select(select)
                .eq("profile_post_id", pid)
                .order("created_at", { ascending: true })
            )
            if (result.error) throw result.error
            comments = (result.data ?? []) as any[]
          } else if (isAchievementFeedPost(post)) {
            const result = await queryAchievementPostComments(async (select) =>
              supabase
                .from("achievement_post_comments")
                .select(select)
                .eq("achievement_post_id", pid)
                .order("created_at", { ascending: true })
            )
            if (result.error) throw result.error
            comments = (result.data ?? []) as any[]
          } else if (isReelFeedPost(post)) {
            const result = await queryReelComments(async (select) =>
              supabase
                .from("reel_comments")
                .select(select)
                .eq("reel_id", pid)
                .order("created_at", { ascending: true })
            )
            if (result.error) throw result.error
            comments = (result.data ?? []) as any[]
          } else {
            const result = await queryFeedComments(async (select) =>
              supabase
                .from("comments")
                .select(select)
                .eq("post_id", pid)
                .order("created_at", { ascending: true })
            )
            if (result.error) throw result.error
            comments = (result.data ?? []) as any[]
          }

          const nextComments = {
            ...commentsByPostRef.current,
            [pid]: comments,
          }
          const nextCounts = {
            ...commentCountsByPostRef.current,
            [pid]: comments.length,
          }
          commentsByPostRef.current = nextComments
          commentCountsByPostRef.current = nextCounts
          commentsLoadedRef.current.add(pid)
          setCommentsByPost(nextComments)
          setCommentCountsByPost(nextCounts)
          persistFeedSnapshot(
            postsRef.current,
            likesByPostRef.current,
            nextComments
          )
          return comments
        } catch (error) {
          console.error("[feed] load comments:", error)
          return commentsByPostRef.current[pid] ?? EMPTY_COMMENTS
        } finally {
          commentsLoadingRef.current.delete(pid)
        }
      })()

      commentsLoadingRef.current.set(pid, request)
      return request
    },
    [persistFeedSnapshot]
  )

  const appendLoadedComment = useCallback(
    (pid: string, comment: any) => {
      const current = commentsByPostRef.current[pid] ?? EMPTY_COMMENTS
      if (current.some((row: any) => row.id === comment.id)) return

      const nextComments = {
        ...commentsByPostRef.current,
        [pid]: [...current, comment],
      }
      const nextCounts = {
        ...commentCountsByPostRef.current,
        [pid]: (commentCountsByPostRef.current[pid] ?? current.length) + 1,
      }
      commentsByPostRef.current = nextComments
      commentCountsByPostRef.current = nextCounts
      commentsLoadedRef.current.add(pid)
      setCommentsByPost(nextComments)
      setCommentCountsByPost(nextCounts)
      persistFeedSnapshot(
        postsRef.current,
        likesByPostRef.current,
        nextComments
      )
    },
    [persistFeedSnapshot]
  )

  const removeLoadedComment = useCallback(
    (pid: string, commentId: string) => {
      const current = commentsByPostRef.current[pid] ?? EMPTY_COMMENTS
      const filtered = filterCommentsAfterDelete(current, commentId)
      if (filtered.length === current.length) return

      const nextComments = {
        ...commentsByPostRef.current,
        [pid]: filtered,
      }
      const nextCounts = {
        ...commentCountsByPostRef.current,
        [pid]: Math.max(
          0,
          (commentCountsByPostRef.current[pid] ?? current.length) -
            (current.length - filtered.length)
        ),
      }
      commentsByPostRef.current = nextComments
      commentCountsByPostRef.current = nextCounts
      setCommentsByPost(nextComments)
      setCommentCountsByPost(nextCounts)
      persistFeedSnapshot(
        postsRef.current,
        likesByPostRef.current,
        nextComments
      )
    },
    [persistFeedSnapshot]
  )

  const patchLoadedComment = useCallback(
    (pid: string, commentId: string, patch: Record<string, unknown>) => {
      const current = commentsByPostRef.current[pid] ?? EMPTY_COMMENTS
      let changed = false
      const nextList = current.map((row: any) => {
        if (String(row.id) !== String(commentId)) return row
        changed = true
        return { ...row, ...patch }
      })
      if (!changed) return

      const nextComments = {
        ...commentsByPostRef.current,
        [pid]: nextList,
      }
      commentsByPostRef.current = nextComments
      setCommentsByPost(nextComments)
      persistFeedSnapshot(
        postsRef.current,
        likesByPostRef.current,
        nextComments
      )
    },
    [persistFeedSnapshot]
  )

  const replaceLoadedComment = useCallback(
    (pid: string, tempId: string, row: any) => {
      const current = commentsByPostRef.current[pid] ?? EMPTY_COMMENTS
      let replaced = false
      const nextList = current.map((comment: any) => {
        if (String(comment.id) !== String(tempId)) return comment
        replaced = true
        return row
      })
      const nextComments = {
        ...commentsByPostRef.current,
        [pid]: replaced ? nextList : [...current, row],
      }
      commentsByPostRef.current = nextComments
      setCommentsByPost(nextComments)
      persistFeedSnapshot(
        postsRef.current,
        likesByPostRef.current,
        nextComments
      )
    },
    [persistFeedSnapshot]
  )

  const loadPosts = useCallback(
    async (pageOverride?: number) => {
      const userId = userIdRef.current
      if (!userId || loadingRef.current || !hasMoreRef.current) return

      const requestGen = feedRequestGenerationRef.current
      const isActive = () => feedRequestGenerationRef.current === requestGen

      const currentPage = pageOverride ?? pageRef.current

      const isInitialPage = currentPage === 0
      if (isInitialPage && !hasLoadedFeedRef.current) {
        if (!isActive()) return
        setLoading(true)
      }
      loadingRef.current = true

      if (currentPage === 0 && isActive()) {
        feedEmptyStateRef.current = null
        setFeedEmptyState(null)
        setFeedLoadError(null)
      }

      try {
        const followingIds = await fetchFollowingIds(supabase, userId)
        if (!isActive()) return

        followingIdsRef.current = followingIds
        if (mode === "following") {
          setFollowingStoryUserIds([...new Set([...followingIds, userId])])
        }

        // Prefer explore/following cache when present; otherwise resolve once from this
        // fetch (already required for scoped feed queries) — no extra DB round-trip.
        if (!defaultModeResolvedRef.current && !userPickedModeRef.current) {
          defaultModeResolvedRef.current = true
          if (followingIds.length > 0 && mode === "global") {
            if (!isActive()) return
            setMode("following")
            return
          }
        }

        let list: FeedItem[] = []

        if (contentType === "all") {
          const toppedUp = await topUpMergedFeedBuffer(supabase, {
            scope: mode,
            userId,
            followingIds,
            buffer: mergeBufferRef.current,
            tradePage: tradePageRef.current,
            profilePage: profilePageRef.current,
            achievementPage: achievementPageRef.current,
            reelPage: reelPageRef.current,
            tradeExhausted: tradeExhaustedRef.current,
            profileExhausted: profileExhaustedRef.current,
            achievementExhausted: achievementExhaustedRef.current,
            reelExhausted: reelExhaustedRef.current,
            targetSize: FEED_PAGE_SIZE,
            pageSize: FEED_PAGE_SIZE,
          })
          if (!isActive()) return

          mergeBufferRef.current = toppedUp.buffer
          tradePageRef.current = toppedUp.tradePage
          profilePageRef.current = toppedUp.profilePage
          achievementPageRef.current = toppedUp.achievementPage
          reelPageRef.current = toppedUp.reelPage
          tradeExhaustedRef.current = toppedUp.tradeExhausted
          profileExhaustedRef.current = toppedUp.profileExhausted
          achievementExhaustedRef.current = toppedUp.achievementExhausted
          reelExhaustedRef.current = toppedUp.reelExhausted

          list = mergeBufferRef.current.splice(0, FEED_PAGE_SIZE)

          if (
            mode === "following" &&
            followingIds.length === 0 &&
            currentPage === 0
          ) {
            if (!isActive()) return
            hasMoreRef.current = false
            setHasMore(false)
            feedEmptyStateRef.current = "following_nobody"
            setFeedEmptyState("following_nobody")
            hasLoadedFeedRef.current = true
            setFeedReady(true)
            return
          }

          if (
            toppedUp.tradeExhausted &&
            toppedUp.profileExhausted &&
            toppedUp.achievementExhausted &&
            toppedUp.reelExhausted &&
            list.length < FEED_PAGE_SIZE
          ) {
            if (!isActive()) return
            hasMoreRef.current = false
            setHasMore(false)
          }

          // All-tab empty: no merged items after every stream is exhausted (or empty).
          if (currentPage === 0 && list.length === 0) {
            feedEmptyStateRef.current = "no_posts"
            setFeedEmptyState("no_posts")
          }
        } else if (contentType === "trades") {
          const result = await fetchTradeFeedBatch(supabase, {
            scope: mode,
            userId,
            followingIds,
            page: currentPage,
            pageSize: FEED_PAGE_SIZE,
          })
          if (!isActive()) return

          if (result.emptyFollowing && currentPage === 0) {
            if (!isActive()) return
            hasMoreRef.current = false
            setHasMore(false)
            feedEmptyStateRef.current = "following_nobody"
            setFeedEmptyState("following_nobody")
            hasLoadedFeedRef.current = true
            setFeedReady(true)
            return
          }

          list = result.items

          if (list.length < FEED_PAGE_SIZE) {
            if (!isActive()) return
            hasMoreRef.current = false
            setHasMore(false)
          }
        } else if (contentType === "posts") {
          const result = await fetchProfileFeedBatch(supabase, {
            scope: mode,
            userId,
            followingIds,
            page: currentPage,
            pageSize: FEED_PAGE_SIZE,
          })
          if (!isActive()) return

          if (result.emptyFollowing && currentPage === 0) {
            if (!isActive()) return
            hasMoreRef.current = false
            setHasMore(false)
            feedEmptyStateRef.current = "following_nobody"
            setFeedEmptyState("following_nobody")
            hasLoadedFeedRef.current = true
            setFeedReady(true)
            return
          }

          list = result.items

          if (list.length < FEED_PAGE_SIZE) {
            if (!isActive()) return
            hasMoreRef.current = false
            setHasMore(false)
          }
        } else if (contentType === "achievements") {
          const result = await fetchAchievementFeedBatch(supabase, {
            scope: mode,
            userId,
            followingIds,
            page: currentPage,
            pageSize: FEED_PAGE_SIZE,
          })
          if (!isActive()) return

          if (result.emptyFollowing && currentPage === 0) {
            if (!isActive()) return
            hasMoreRef.current = false
            setHasMore(false)
            feedEmptyStateRef.current = "following_nobody"
            setFeedEmptyState("following_nobody")
            hasLoadedFeedRef.current = true
            setFeedReady(true)
            return
          }

          list = result.items

          if (list.length < FEED_PAGE_SIZE) {
            if (!isActive()) return
            hasMoreRef.current = false
            setHasMore(false)
          }
        } else if (contentType === "reels") {
          const result = await fetchReelFeedBatch(supabase, {
            scope: mode,
            userId,
            followingIds,
            page: currentPage,
            pageSize: FEED_PAGE_SIZE,
          })
          if (!isActive()) return

          if (result.emptyFollowing && currentPage === 0) {
            if (!isActive()) return
            hasMoreRef.current = false
            setHasMore(false)
            feedEmptyStateRef.current = "following_nobody"
            setFeedEmptyState("following_nobody")
            hasLoadedFeedRef.current = true
            setFeedReady(true)
            return
          }

          list = result.items

          if (list.length < FEED_PAGE_SIZE) {
            if (!isActive()) return
            hasMoreRef.current = false
            setHasMore(false)
          }
        }

        if (!isActive()) return

        const painted =
          currentPage === 0 ? list : [...postsRef.current, ...list]

        postsRef.current = painted
        setPosts(painted)

        if (currentPage === 0 && list.length === 0) {
          // Keep ref in sync so session snapshots never persist an empty feed
          // without an empty-state marker (which rendered as a blank All tab).
          if (feedEmptyStateRef.current == null) {
            feedEmptyStateRef.current = "no_posts"
            setFeedEmptyState("no_posts")
          }
        }

        const { enriched, likesMap, commentCountsMap } = await loadEngagementForPosts(
          list,
          { id: userId }
        )
        if (!isActive()) return

        const enrichedById = new Map(
          enriched.map((p) => [String(p.id), p] as const)
        )
        const nextPosts = painted.map(
          (p) => enrichedById.get(String(p.id)) ?? p
        )
        const mergedLikes = { ...likesByPostRef.current, ...likesMap }
        const mergedCommentCounts = {
          ...commentCountsByPostRef.current,
          ...commentCountsMap,
        }
        postsRef.current = nextPosts
        setPosts(nextPosts)
        setLikesByPost(mergedLikes)
        commentCountsByPostRef.current = mergedCommentCounts
        setCommentCountsByPost(mergedCommentCounts)

        if (currentPage === 0) {
          hasLoadedFeedRef.current = true
          setFeedReady(true)
        }

        persistFeedSnapshot(nextPosts, mergedLikes, commentsByPostRef.current, {
          hasLoaded: hasLoadedFeedRef.current,
          feedEmptyState: feedEmptyStateRef.current,
        }, requestGen)

        const nextPage =
          pageOverride != null ? pageOverride + 1 : pageRef.current + 1
        pageRef.current = nextPage
        setPage(nextPage)
      } catch (error) {
        const supabaseError =
          error &&
          typeof error === "object" &&
          "code" in error &&
          "message" in error
        if (supabaseError) {
          console.error(
            "[feed] loadPosts FULL ERROR",
            JSON.stringify(error, null, 2)
          )
        } else {
          console.error("[feed] loadPosts FULL ERROR", error)
        }
        if (isActive() && currentPage === 0) {
          setFeedLoadError("Couldn't load the feed. Please try again.")
          hasLoadedFeedRef.current = true
          setFeedReady(true)
        }
      } finally {
        if (isActive()) {
          loadingRef.current = false
          setLoading(false)
        }
      }
    },
    [mode, contentType, loadEngagementForPosts, persistFeedSnapshot]
  )

  const resetFeedState = useCallback(() => {
    hasLoadedFeedRef.current = false
    setFeedReady(false)
    setPosts([])
    setLikesByPost({})
    setCommentCountsByPost({})
    setCommentsByPost({})
    commentCountsByPostRef.current = {}
    commentsLoadedRef.current.clear()
    commentsLoadingRef.current.clear()
    setFeedEmptyState(null)
    feedEmptyStateRef.current = null
    setFeedLoadError(null)
    setPage(0)
    setHasMore(true)
    pageRef.current = 0
    hasMoreRef.current = true
    loadingRef.current = false
    mergeBufferRef.current = []
    tradePageRef.current = 0
    profilePageRef.current = 0
    achievementPageRef.current = 0
    reelPageRef.current = 0
    tradeExhaustedRef.current = false
    profileExhaustedRef.current = false
    achievementExhaustedRef.current = false
    reelExhaustedRef.current = false
  }, [])

  const restoreFeedSession = useCallback((key: string, cached: FeedSessionSnapshot) => {
    feedInitKeyRef.current = key
    setPosts(cached.posts)
    setLikesByPost(cached.likesByPost)
    const cachedCommentCounts =
      cached.commentCountsByPost ??
      Object.fromEntries(
        Object.entries(cached.commentsByPost).map(([id, comments]) => [
          id,
          comments.length,
        ])
      )
    commentCountsByPostRef.current = cachedCommentCounts
    setCommentCountsByPost(cachedCommentCounts)
    setCommentsByPost(cached.commentsByPost)
    commentsByPostRef.current = cached.commentsByPost
    commentsLoadedRef.current = new Set(Object.keys(cached.commentsByPost))
    feedEmptyStateRef.current = cached.feedEmptyState
    setFeedEmptyState(cached.feedEmptyState)
    setFeedLoadError(null)
    setPage(cached.page)
    setHasMore(cached.hasMore)
    pageRef.current = cached.page
    hasMoreRef.current = cached.hasMore
    mergeBufferRef.current = [...cached.mergeBuffer]
    tradePageRef.current = cached.tradePage
    profilePageRef.current = cached.profilePage
    achievementPageRef.current = cached.achievementPage ?? 0
    reelPageRef.current = cached.reelPage ?? 0
    tradeExhaustedRef.current = cached.tradeExhausted
    profileExhaustedRef.current = cached.profileExhausted
    achievementExhaustedRef.current = cached.achievementExhausted ?? false
    reelExhaustedRef.current = cached.reelExhausted ?? false
    hasLoadedFeedRef.current = cached.hasLoaded
    setFeedReady(cached.hasLoaded)
    loadingRef.current = false
    setLoading(false)
    scrollYRef.current = cached.scrollY
    if (cached.scrollY > 0) {
      requestAnimationFrame(() => {
        window.scrollTo(0, cached.scrollY)
      })
    }
  }, [])

  useEffect(() => {
    if (!user?.id || !feedDefaultModeReady) return

    const feedInitKey = `${user.id}:${mode}:${contentType}`
    if (feedInitKeyRef.current === feedInitKey && hasLoadedFeedRef.current) {
      return
    }

    const cached = readFeedSession(feedInitKey)
    if (cached?.hasLoaded) {
      bumpFeedRequestGeneration()
      restoreFeedSession(feedInitKey, cached)
      return
    }

    bumpFeedRequestGeneration()
    feedInitKeyRef.current = feedInitKey
    resetFeedState()
    setLoading(true)
    void loadPosts(0)
  }, [
    user?.id,
    mode,
    contentType,
    feedDefaultModeReady,
    loadPosts,
    resetFeedState,
    restoreFeedSession,
    bumpFeedRequestGeneration,
  ])

  useEffect(() => {
    if (!user?.id || isDemoModeActive()) return
    if (contentType !== "all" && contentType !== "trades") return

    const userId = user.id
    const realtimeGeneration = feedRequestGenerationRef.current
    const channel = supabase.channel(`feed-trade-posts-${userId}`)

    channel.on(
      "postgres_changes",
      { event: "INSERT", schema: "public", table: "posts" },
      async (payload) => {
        const row = payload.new as Record<string, unknown>
        const authorId = String(row.user_id ?? "")
        if (!authorId || authorId === userId) return
        if (mode === "following" && !followingIdsRef.current.includes(authorId)) {
          return
        }
        if (
          mode === "global" &&
          followingIdsRef.current.includes(authorId)
        ) {
          return
        }

        const { data } = await supabase
          .from("posts")
          .select(FEED_POSTS_SELECT)
          .eq("id", String(row.id))
          .maybeSingle()

        if (!data) return
        if (realtimeGeneration !== feedRequestGenerationRef.current) return

        // INSERT rows cannot have engagement yet in the normal creation flow.
        // Seed empty metadata and let the existing engagement realtime handlers
        // apply later changes instead of issuing a global engagement refetch.
        const post = normalizeTradeFeedItem(data as Record<string, unknown>)
        const postId = String(post.id)
        const likesMap = { [postId]: { count: 0, liked: false } }
        const commentCountsMap = { [postId]: 0 }

        setPosts((prev) => {
          if (realtimeGeneration !== feedRequestGenerationRef.current) return prev
          if (prev.some((p) => String(p.id) === String(post.id))) return prev
          const next = [post, ...prev]
          const mergedLikes = {
            ...likesByPostRef.current,
            ...likesMap,
          }
          const mergedCommentCounts = {
            ...commentCountsByPostRef.current,
            ...commentCountsMap,
          }
          commentCountsByPostRef.current = mergedCommentCounts
          setCommentCountsByPost(mergedCommentCounts)
          persistFeedSnapshot(
            next,
            mergedLikes,
            commentsByPostRef.current,
            undefined,
            realtimeGeneration
          )
          setLikesByPost(mergedLikes)
          return next
        })
      }
    )

    channel.subscribe()
    return () => {
      void supabase.removeChannel(channel)
    }
  }, [user?.id, mode, contentType, persistFeedSnapshot])

  useEffect(() => {
    if (!user?.id || isDemoModeActive()) return
    if (contentType !== "all" && contentType !== "posts") return

    const userId = user.id
    const realtimeGeneration = feedRequestGenerationRef.current
    const channel = supabase.channel(`feed-profile-posts-${userId}`)

    channel.on(
      "postgres_changes",
      { event: "INSERT", schema: "public", table: "profile_posts" },
      async (payload) => {
        const row = payload.new as Record<string, unknown>
        const authorId = String(row.user_id ?? "")
        if (!authorId || authorId === userId) return
        if (mode === "following" && !followingIdsRef.current.includes(authorId)) {
          return
        }
        if (
          mode === "global" &&
          followingIdsRef.current.includes(authorId)
        ) {
          return
        }

        const { data } = await supabase
          .from("profile_posts")
          .select(FEED_PROFILE_POSTS_SELECT)
          .eq("id", String(row.id))
          .maybeSingle()

        if (!data) return
        if (realtimeGeneration !== feedRequestGenerationRef.current) return

        const post = normalizeProfileFeedItem(data as Record<string, unknown>)
        const postId = String(post.id)
        const likesMap = { [postId]: { count: 0, liked: false } }
        const commentCountsMap = { [postId]: 0 }

        setPosts((prev) => {
          if (realtimeGeneration !== feedRequestGenerationRef.current) return prev
          if (prev.some((p) => String(p.id) === String(post.id))) return prev
          const next = [post, ...prev]
          const mergedLikes = {
            ...likesByPostRef.current,
            ...likesMap,
          }
          const mergedCommentCounts = {
            ...commentCountsByPostRef.current,
            ...commentCountsMap,
          }
          commentCountsByPostRef.current = mergedCommentCounts
          setCommentCountsByPost(mergedCommentCounts)
          persistFeedSnapshot(
            next,
            mergedLikes,
            commentsByPostRef.current,
            undefined,
            realtimeGeneration
          )
          setLikesByPost(mergedLikes)
          return next
        })
      }
    )

    channel.subscribe()
    return () => {
      void supabase.removeChannel(channel)
    }
  }, [user?.id, mode, contentType, persistFeedSnapshot])

  useEffect(() => {
    if (!user?.id || isDemoModeActive()) return
    if (contentType !== "all" && contentType !== "achievements") return

    const userId = user.id
    const realtimeGeneration = feedRequestGenerationRef.current
    const channel = supabase.channel(`feed-achievement-posts-${userId}`)

    channel.on(
      "postgres_changes",
      { event: "INSERT", schema: "public", table: "achievement_posts" },
      async (payload) => {
        const row = payload.new as Record<string, unknown>
        const authorId = String(row.user_id ?? "")
        if (!authorId || authorId === userId) return
        if (mode === "following" && !followingIdsRef.current.includes(authorId)) {
          return
        }
        if (
          mode === "global" &&
          followingIdsRef.current.includes(authorId)
        ) {
          return
        }

        const { data } = await supabase
          .from("achievement_posts")
          .select(FEED_ACHIEVEMENT_POSTS_SELECT)
          .eq("id", String(row.id))
          .eq("achievements.is_public", true)
          .maybeSingle()

        if (!data) return
        if (realtimeGeneration !== feedRequestGenerationRef.current) return

        const post = normalizeAchievementFeedItem(data as Record<string, unknown>)
        const postId = String(post.id)
        const likesMap = { [postId]: { count: 0, liked: false } }
        const commentCountsMap = { [postId]: 0 }

        setPosts((prev) => {
          if (realtimeGeneration !== feedRequestGenerationRef.current) return prev
          if (prev.some((p) => String(p.id) === String(post.id))) return prev
          const next = [post, ...prev]
          const mergedLikes = {
            ...likesByPostRef.current,
            ...likesMap,
          }
          const mergedCommentCounts = {
            ...commentCountsByPostRef.current,
            ...commentCountsMap,
          }
          commentCountsByPostRef.current = mergedCommentCounts
          setCommentCountsByPost(mergedCommentCounts)
          persistFeedSnapshot(
            next,
            mergedLikes,
            commentsByPostRef.current,
            undefined,
            realtimeGeneration
          )
          setLikesByPost(mergedLikes)
          return next
        })
      }
    )

    channel.subscribe()
    return () => {
      void supabase.removeChannel(channel)
    }
  }, [user?.id, mode, contentType, persistFeedSnapshot])

  useEffect(() => {
    if (!user?.id || isDemoModeActive()) return
    if (contentType !== "all" && contentType !== "reels") return

    const userId = user.id
    const realtimeGeneration = feedRequestGenerationRef.current
    const channel = supabase.channel(`feed-reels-${userId}`)

    channel.on(
      "postgres_changes",
      { event: "INSERT", schema: "public", table: "reels" },
      async (payload) => {
        const row = payload.new as Record<string, unknown>
        const authorId = String(row.user_id ?? "")
        if (!authorId || authorId === userId) return
        if (mode === "following" && !followingIdsRef.current.includes(authorId)) {
          return
        }
        if (
          mode === "global" &&
          followingIdsRef.current.includes(authorId)
        ) {
          return
        }

        const { data } = await supabase
          .from("reels")
          .select(FEED_REELS_SELECT)
          .eq("id", String(row.id))
          .maybeSingle()

        if (!data) return
        if (realtimeGeneration !== feedRequestGenerationRef.current) return

        const post = normalizeReelFeedItem(data as Record<string, unknown>)
        // Match dedupeFeedItems: trade-attached reels already render on the trade card.
        if (
          post.trade_id != null &&
          String(post.trade_id).trim() !== "" &&
          (contentType === "all" || contentType === "trades")
        ) {
          return
        }
        const postId = String(post.id)
        const likesMap = { [postId]: { count: 0, liked: false } }
        const commentCountsMap = { [postId]: 0 }

        setPosts((prev) => {
          if (realtimeGeneration !== feedRequestGenerationRef.current) return prev
          if (prev.some((p) => String(p.id) === String(post.id))) return prev
          const next = [post, ...prev]
          const mergedLikes = {
            ...likesByPostRef.current,
            ...likesMap,
          }
          const mergedCommentCounts = {
            ...commentCountsByPostRef.current,
            ...commentCountsMap,
          }
          commentCountsByPostRef.current = mergedCommentCounts
          setCommentCountsByPost(mergedCommentCounts)
          persistFeedSnapshot(
            next,
            mergedLikes,
            commentsByPostRef.current,
            undefined,
            realtimeGeneration
          )
          setLikesByPost(mergedLikes)
          return next
        })
      }
    )

    channel.subscribe()
    return () => {
      void supabase.removeChannel(channel)
    }
  }, [user?.id, mode, contentType, persistFeedSnapshot])

  useEffect(() => {
    if (!user?.id || isDemoModeActive()) return

    const userId = user.id
    const reelIds = postsRef.current
      .filter((p) => isReelFeedPost(p))
      .map((p) => String(p.id))

    if (reelIds.length === 0) return

    const realtimeGeneration = feedRequestGenerationRef.current
    const channel = supabase.channel(`feed-reel-likes-${userId}`)

    const refreshReelLike = (reelId: string) => {
      void (async () => {
        const metaById = await fetchReelLikeMetaByIds(
          supabase,
          [reelId],
          userId
        )
        if (realtimeGeneration !== feedRequestGenerationRef.current) return
        const next = metaById[reelId]
        if (!next) return

        setLikesByPost((prev) => {
          if (realtimeGeneration !== feedRequestGenerationRef.current) return prev
          const merged = { ...prev, [reelId]: next }
          persistFeedSnapshot(
            postsRef.current,
            merged,
            commentsByPostRef.current,
            undefined,
            realtimeGeneration
          )
          return merged
        })
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
  }, [user?.id, posts, persistFeedSnapshot])

  useEffect(() => {
    const handleScroll = () => {
      scrollYRef.current = window.scrollY
      const key = feedInitKeyRef.current
      if (key && hasLoadedFeedRef.current) {
        const cached = readFeedSession(key)
        if (cached) {
          writeFeedSession(key, { ...cached, scrollY: window.scrollY })
        }
      }
      if (window.innerHeight + window.scrollY >= document.body.offsetHeight - 200) {
        void loadPosts()
      }
    }

    window.addEventListener("scroll", handleScroll)
    return () => window.removeEventListener("scroll", handleScroll)
  }, [loadPosts])

  const handleSelectPost = useCallback(
    (post: any) => {
      void import("@/lib/nativeHaptics").then(({ hapticLight }) => {
        hapticLight("open-trade-card")
      })
      void loadCommentsForPost(post)
      setFeedModalPost(null)
      feedDeepLinkHandledRef.current = null
      clearFeedDeepLinkParams()
      setSelectedPostId(String(post.id))
    },
    [clearFeedDeepLinkParams, loadCommentsForPost]
  )

  const handleOpenPostComments = useCallback(
    (post: any) => {
      const pid = String(post.id)
      void loadCommentsForPost(post)
      openCommentsRef.current[pid] = true
      setFeedModalPost(null)
      feedDeepLinkHandledRef.current = null
      clearFeedDeepLinkParams()
      setSelectedPostId(pid)
    },
    [clearFeedDeepLinkParams, loadCommentsForPost]
  )

  const handleOpenLinkedTrade = useCallback(
    (post: any) => {
      const pid = String(post.id)
      void loadCommentsForPost(post)
      openTradeRef.current[pid] = true
      if (selectedPostId === pid) {
        setTradeExpandSignal((value) => value + 1)
        return
      }
      setFeedModalPost(null)
      feedDeepLinkHandledRef.current = null
      clearFeedDeepLinkParams()
      setSelectedPostId(pid)
    },
    [clearFeedDeepLinkParams, loadCommentsForPost, selectedPostId]
  )

  const handleOpenAttachedReel = useCallback(
    (post: any, reel: ReelRow) => {
      const reelPost = reelDetailFeedItem(
        {
          ...reel,
          user_id: reel.user_id ?? post.user_id,
        },
        post.profiles
      )
      void loadCommentsForPost(reelPost)
      setStackedAttachedReel(reelPost)
    },
    [loadCommentsForPost]
  )

  const handleCloseStackedAttachedReel = useCallback(() => {
    setStackedAttachedReel(null)
  }, [])

  const handleSharePost = useCallback((post: any) => {
    if (guardDemoFeedWrite("default")) return
    setSharePostId(String(post.id))
  }, [])

  const handleCloseDetailModal = useCallback(() => {
    setSelectedPostId(null)
    setFeedModalPost(null)
    setStackedAttachedReel(null)
    feedDeepLinkHandledRef.current = null
    clearFeedDeepLinkParams()
  }, [clearFeedDeepLinkParams])

  const handleCloseShareOverlay = useCallback(() => {
    setSharePostId(null)
  }, [])

  const patchFeedReel = useCallback(
    (reelId: string, patch: Record<string, unknown>) => {
      setPosts((prev) => {
        const next = prev.map((p) =>
          isReelFeedPost(p) && String(p.id) === reelId ? { ...p, ...patch } : p
        )
        postsRef.current = next
        persistFeedSnapshot(
          next,
          likesByPostRef.current,
          commentsByPostRef.current
        )
        return next
      })
      setFeedModalPost((prev) =>
        prev && isReelFeedPost(prev) && String(prev.id) === reelId
          ? { ...prev, ...patch }
          : prev
      )
      const uid = userIdRef.current
      if (uid) patchFeedReelInSessionsForUser(uid, reelId, patch)
    },
    [persistFeedSnapshot]
  )

  const handleReelMenuToggle = useCallback((reelId: string) => {
    setOpenReelMenuId((prev) => (prev === reelId ? null : reelId))
  }, [])

  const handleStartEditReel = useCallback(
    (post: any) => {
      if (guardDemoFeedWrite("edit")) return
      if (!user?.id || String(post.user_id) !== String(user.id)) return
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
      setOpenReelMenuId(null)
    },
    [user?.id]
  )

  const handleReplaceReelVideo = useCallback(
    (post: any) => {
      if (guardDemoFeedWrite("edit")) return
      if (!user?.id || String(post.user_id) !== String(user.id)) return
      if (!isTradeAttachedReel(post)) return
      setReplacingReelPost(post)
      setOpenReelMenuId(null)
      replaceReelInputRef.current?.click()
    },
    [user?.id]
  )

  const handleReplaceReelFileSelected = useCallback(
    async (file: File | null) => {
      if (!file || !replacingReelPost || !user?.id) return

      const reelId = String(replacingReelPost.id)
      const snapshotPost = replacingReelPost
      setReplacingReelPost(null)

      try {
        await runUpload({
          title: "Uploading Clip",
          execute: async (report) => {
            const result = await replaceTradeReelVideo(supabase, {
              reelId,
              userId: user.id,
              file,
              onProgress: report,
            })

            if ("error" in result) {
              throw new Error(result.error)
            }

            const updated = result.reel
            patchFeedReel(reelId, {
              video_url: updated.video_url,
              thumbnail_url: updated.thumbnail_url,
              duration_seconds: updated.duration_seconds,
              updated_at: updated.updated_at,
            })
            if (selectedPostId === reelId) {
              setFeedModalPost((prev) =>
                prev && String(prev.id) === reelId ? { ...prev, ...updated } : prev
              )
            }
          },
        })
      } catch {
        setReplacingReelPost(snapshotPost)
      }
    },
    [patchFeedReel, replacingReelPost, runUpload, selectedPostId, user?.id]
  )

  const handleReelSaved = useCallback(
    (reel: ReelRow) => {
      if (guardDemoFeedWrite("save")) return
      patchFeedReel(String(reel.id), {
        caption: reel.caption,
        updated_at: reel.updated_at,
      })
      setEditingReel(null)
      setOpenReelMenuId(null)
    },
    [patchFeedReel]
  )

  const performDeleteReel = useCallback(
    async (post: any) => {
      if (guardDemoFeedWrite("delete")) return
      if (!user?.id || String(post.user_id) !== String(user.id)) return

      const reelId = String(post.id)
      const result = await deleteReel(supabase, {
        reelId,
        userId: user.id,
      })

      if ("error" in result) {
        showPopup({ type: "error", message: handleSupabaseError(result.error) })
        return
      }

      setPosts((prev) => {
        const next = prev.filter(
          (p) => !(isReelFeedPost(p) && String(p.id) === reelId)
        )
        postsRef.current = next
        persistFeedSnapshot(
          next,
          likesByPostRef.current,
          commentsByPostRef.current
        )
        return next
      })
      removeFeedReelFromSessionsForUser(user.id, reelId)
      setOpenReelMenuId(null)
      if (selectedPostId === reelId) {
        setSelectedPostId(null)
        setFeedModalPost(null)
        feedDeepLinkHandledRef.current = null
        clearFeedDeepLinkParams()
      }
    },
    [user?.id, persistFeedSnapshot, selectedPostId, showPopup, clearFeedDeepLinkParams]
  )

  const {
    requestDelete: requestDeleteReel,
    confirmModalProps: deleteReelConfirmProps,
  } = useDeleteReelConfirmation(performDeleteReel)

  const toggleLike = useCallback(
    async (post: any) => {
      if (guardDemoFeedWrite("like")) return
      if (!user) return

      const pid = String(post.id)
      const isProfile = isProfileFeedPost(post)
      const isAchievement = isAchievementFeedPost(post)
      const isReel = isReelFeedPost(post)
      if (likeBusyRef.current.has(pid)) return

      likeBusyRef.current.add(pid)
      setLikeBusyByPost((prev) => ({ ...prev, [pid]: true }))

      const applyMeta = (next: { count: number; liked: boolean }) => {
        setLikesByPost((prev) => {
          const merged = { ...prev, [pid]: next }
          persistFeedSnapshot(
            postsRef.current,
            merged,
            commentsByPostRef.current
          )
          return merged
        })
      }

      try {
        const meta = likesByPostRef.current[pid] ?? EMPTY_LIKE_META

        if (isReel) {
          const ok = await toggleReelLike(supabase, {
            reelId: pid,
            userId: user.id,
            ownerUserId: reelOwnerUserId(post),
            meta,
            onMetaChange: applyMeta,
          })
          if (!ok) {
            showPopup({
              type: "error",
              message: "Couldn't update like. Please try again.",
            })
          }
          return
        }

        const kind = isProfile
          ? "profile_post"
          : isAchievement
            ? "achievement_post"
            : "post"
        const ownerId = isProfile
          ? profilePostOwnerUserId(post)
          : isAchievement
            ? achievementPostOwnerUserId(post)
            : postTradeOwnerUserId(post)

        const ok = await toggleContentLike(supabase, {
          kind,
          contentId: pid,
          userId: user.id,
          ownerUserId: ownerId,
          meta,
          tradeId: post.trade_id ?? null,
          onMetaChange: applyMeta,
        })
        if (!ok) {
          showPopup({
            type: "error",
            message: "Couldn't update like. Please try again.",
          })
        }
      } finally {
        likeBusyRef.current.delete(pid)
        setLikeBusyByPost((prev) => ({ ...prev, [pid]: false }))
      }
    },
    [user, persistFeedSnapshot, showPopup]
  )

  const submitComment = useCallback(
    async (
      post: any,
      text: string,
      parentCommentId?: string | null,
      retryTempId?: string | null
    ) => {
      if (guardDemoFeedWrite("comment")) return false
      if (!user) return false

      const pid = String(post.id)
      const trimmed = (text || "").trim()
      if (!trimmed) return false
      if (commentSubmittingRef.current.has(pid)) return false

      commentSubmittingRef.current.add(pid)
      setCommentSubmitting((s) => ({ ...s, [pid]: true }))

      void import("@/lib/nativeHaptics").then(({ hapticMedium }) => {
        hapticMedium("submit-comment")
      })

      try {
      const isProfile = isProfileFeedPost(post)
      const isAchievement = isAchievementFeedPost(post)
      const isReel = isReelFeedPost(post)
      const existingComments = commentsByPostRef.current[pid] ?? EMPTY_COMMENTS
      const tempId = retryTempId ?? createOptimisticTempId("temp-c")

      if (retryTempId) {
        patchLoadedComment(pid, tempId, { sync_status: "posting", content: trimmed })
      } else {
        const optimisticComment = {
          id: tempId,
          content: trimmed,
          user_id: user.id,
          created_at: new Date().toISOString(),
          parent_comment_id: parentCommentId ?? null,
          sync_status: "posting",
          profiles: { username: null, avatar_url: null },
        }
        appendLoadedComment(pid, optimisticComment)
      }

      const failOptimistic = () =>
        patchLoadedComment(pid, tempId, { sync_status: "failed" })
      const confirmOptimistic = (row: any) => {
        replaceLoadedComment(pid, tempId, row)
      }

      if (isProfile) {
        const insertPayload: Record<string, unknown> = {
          profile_post_id: pid,
          user_id: user.id,
          content: trimmed,
        }
        if (parentCommentId) {
          insertPayload.parent_comment_id = parentCommentId
        }

        const { data: newRow, error } = await supabase
          .from("profile_post_comments")
          .insert(insertPayload)
          .select(PROFILE_POST_COMMENT_INSERT_SELECT)
          .single()

        if (error) {
          console.error("[profile-post-comment] insert failed", {
            userId: user.id,
            profilePostId: pid,
            commentText: trimmed,
            parentCommentId: parentCommentId ?? null,
            payload: insertPayload,
            supabaseError: {
              code: error.code,
              message: error.message,
              details: error.details,
              hint: error.hint,
            },
          })
          failOptimistic()
          return true
        }

        const insertedRow = withInsertedProfilePostParentCommentId(
          newRow,
          parentCommentId
        )

        confirmOptimistic(insertedRow)

        const ownerId = profilePostOwnerUserId(post)
        if (ownerId) {
          await insertProfilePostCommentNotifications(supabase, {
            profilePostId: pid,
            commentId: String(insertedRow.id),
            ownerUserId: ownerId,
            senderUserId: user.id,
            content: trimmed,
            parentCommentId,
            existingComments,
          })
        }

        return true
      }

      if (isReel) {
        const insertPayload: Record<string, unknown> = {
          reel_id: pid,
          user_id: user.id,
          content: trimmed,
        }
        if (parentCommentId) {
          insertPayload.parent_comment_id = parentCommentId
        }

        const { data: newRow, error } = await supabase
          .from("reel_comments")
          .insert(insertPayload)
          .select(REEL_COMMENT_INSERT_SELECT)
          .single()

        if (error) {
          console.error("[reel-comment] insert failed", {
            userId: user.id,
            reelId: pid,
            commentText: trimmed,
            parentCommentId: parentCommentId ?? null,
            payload: insertPayload,
            supabaseError: {
              code: error.code,
              message: error.message,
              details: error.details,
              hint: error.hint,
            },
          })
          failOptimistic()
          return true
        }

        const insertedRow = withInsertedReelParentCommentId(
          newRow,
          parentCommentId
        )

        confirmOptimistic(insertedRow)

        const ownerId = reelOwnerUserId(post)
        if (ownerId) {
          await insertReelCommentNotifications(supabase, {
            reelId: pid,
            commentId: String(insertedRow.id),
            ownerUserId: ownerId,
            senderUserId: user.id,
            content: trimmed,
            parentCommentId,
            existingComments,
          })
        }

        return true
      }

      if (isAchievement) {
        const insertPayload: Record<string, unknown> = {
          achievement_post_id: pid,
          user_id: user.id,
          content: trimmed,
        }
        if (parentCommentId) {
          insertPayload.parent_comment_id = parentCommentId
        }

        const { data: newRow, error } = await supabase
          .from("achievement_post_comments")
          .insert(insertPayload)
          .select(ACHIEVEMENT_POST_COMMENT_INSERT_SELECT)
          .single()

        if (error) {
          console.error("[achievement-post-comment] insert failed", {
            userId: user.id,
            achievementPostId: pid,
            commentText: trimmed,
            parentCommentId: parentCommentId ?? null,
            payload: insertPayload,
            supabaseError: {
              code: error.code,
              message: error.message,
              details: error.details,
              hint: error.hint,
            },
          })
          failOptimistic()
          return true
        }

        const insertedRow = withInsertedAchievementPostParentCommentId(
          newRow,
          parentCommentId
        )

        confirmOptimistic(insertedRow)

        const ownerId = achievementPostOwnerUserId(post)
        if (ownerId) {
          await insertAchievementPostCommentNotifications(supabase, {
            achievementPostId: pid,
            commentId: String(insertedRow.id),
            ownerUserId: ownerId,
            senderUserId: user.id,
            content: trimmed,
            parentCommentId,
            existingComments,
          })
        }

        return true
      }

      const insertPayload: Record<string, unknown> = {
        post_id: pid,
        user_id: user.id,
        content: trimmed,
      }
      if (parentCommentId) {
        insertPayload.parent_comment_id = parentCommentId
      }

      const { data: newRow, error } = await supabase
        .from("comments")
        .insert(insertPayload)
        .select(FEED_COMMENT_INSERT_SELECT)
        .single()

      if (error) {
        console.error("[post-comment] insert failed", {
          userId: user.id,
          postId: pid,
          feedKind: post.feedKind ?? "unknown",
          commentText: trimmed,
          parentCommentId: parentCommentId ?? null,
          payload: insertPayload,
          supabaseError: {
            code: error.code,
            message: error.message,
            details: error.details,
            hint: error.hint,
          },
        })
        failOptimistic()
        return true
      }

      const insertedRow = withInsertedParentCommentId(newRow, parentCommentId)

      confirmOptimistic(insertedRow)

      const notifyUserId = postTradeOwnerUserId(post)
      await ensureCommentNotificationsForInsert(supabase, {
        commentId: String(insertedRow.id),
        senderUserId: user.id,
        content: trimmed,
        target: { kind: "post", postId: pid, tradeId: post.trade_id ?? null },
        ownerUserId: notifyUserId,
        parentCommentId,
        existingComments,
      })

      return true
      } finally {
        commentSubmittingRef.current.delete(pid)
        setCommentSubmitting((s) => ({ ...s, [pid]: false }))
      }
    },
    [user, appendLoadedComment, patchLoadedComment, replaceLoadedComment]
  )

  const deleteComment = useCallback(
    async (comment: any) => {
      if (guardDemoFeedWrite("delete")) return false
      if (!user) {
        console.warn("[comment-delete] aborted: no user")
        return false
      }

      const restoreComment = (postId: string, snapshot: any[]) => {
        const nextComments = {
          ...commentsByPostRef.current,
          [postId]: snapshot,
        }
        commentsByPostRef.current = nextComments
        setCommentsByPost(nextComments)
        persistFeedSnapshot(
          postsRef.current,
          likesByPostRef.current,
          nextComments
        )
      }

      const profilePostId = String(comment.profile_post_id ?? "")
      if (profilePostId) {
        const snapshot =
          commentsByPostRef.current[profilePostId] ?? EMPTY_COMMENTS
        removeLoadedComment(profilePostId, String(comment.id))
        const { error, deleted } = await deleteProfilePostComment(supabase, {
          id: String(comment.id),
          user_id: user.id,
          content: comment.content,
          profile_post_id: profilePostId,
        })

        if (error || !deleted) {
          console.error("[comment-delete] failed", {
            commentId: String(comment.id),
            userId: user.id,
            profilePostId,
            error,
          })
          restoreComment(profilePostId, snapshot)
          showPopup({ type: "error", message: handleSupabaseError(error) })
          return false
        }

        return true
      }

      const achievementPostId = String(comment.achievement_post_id ?? "")
      if (achievementPostId) {
        const snapshot =
          commentsByPostRef.current[achievementPostId] ?? EMPTY_COMMENTS
        removeLoadedComment(achievementPostId, String(comment.id))
        const { error, deleted } = await deleteAchievementPostComment(supabase, {
          id: String(comment.id),
          user_id: user.id,
          content: comment.content,
          achievement_post_id: achievementPostId,
        })

        if (error || !deleted) {
          console.error("[comment-delete] failed", {
            commentId: String(comment.id),
            userId: user.id,
            achievementPostId,
            error,
          })
          restoreComment(achievementPostId, snapshot)
          showPopup({ type: "error", message: handleSupabaseError(error) })
          return false
        }

        return true
      }

      const reelId = String(comment.reel_id ?? "")
      if (reelId) {
        const snapshot = commentsByPostRef.current[reelId] ?? EMPTY_COMMENTS
        removeLoadedComment(reelId, String(comment.id))
        const { error, deleted } = await deleteReelComment(supabase, {
          id: String(comment.id),
          user_id: user.id,
          content: comment.content,
          reel_id: reelId,
        })

        if (error || !deleted) {
          console.error("[comment-delete] failed", {
            commentId: String(comment.id),
            userId: user.id,
            reelId,
            error,
          })
          restoreComment(reelId, snapshot)
          showPopup({ type: "error", message: handleSupabaseError(error) })
          return false
        }

        return true
      }

      const postId = String(comment.post_id ?? "")
      if (!postId) return false
      const snapshot = commentsByPostRef.current[postId] ?? EMPTY_COMMENTS
      removeLoadedComment(postId, String(comment.id))
      const { error, deleted } = await deleteFeedComment(supabase, {
        id: String(comment.id),
        user_id: user.id,
        content: comment.content,
        post_id: postId,
      })

      if (error || !deleted) {
        console.error("[comment-delete] failed", {
          commentId: String(comment.id),
          userId: user.id,
          postId,
          error,
        })
        restoreComment(postId, snapshot)
        showPopup({ type: "error", message: handleSupabaseError(error) })
        return false
      }

      return true
    },
    [user, showPopup, removeLoadedComment, persistFeedSnapshot]
  )

  const { uniquePosts, postsById } = useMemo(
    () => buildFeedPostsIndex(posts),
    [posts]
  )

  const togglePinComment = useCallback(
    async (comment: any, pinned: boolean) => {
      if (!user) return false
      if (comment.parent_comment_id) return false

      const target = resolveCommentPinTarget(comment)
      if (!target) {
        console.error("[comment-pin] aborted: missing comment target", comment)
        return false
      }

      const contentPost =
        postsById.get(target.stateKey) ??
        (feedModalPost && String(feedModalPost.id) === target.stateKey
          ? feedModalPost
          : null)
      const ownerId = feedContentOwnerUserId(contentPost)

      if (
        !canPinComment({
          viewerUserId: user.id,
          contentOwnerUserId: ownerId,
        })
      ) {
        return false
      }

      const commentId = String(comment.id)
      let previous: any[] = []
      setCommentsByPost((prev) => {
        previous = prev[target.stateKey] ?? EMPTY_COMMENTS
        return {
          ...prev,
          [target.stateKey]: applyPinnedCommentState(previous, commentId, pinned),
        }
      })

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
        showPopup({ type: "error", message: handleSupabaseError(error) })
        return false
      }

      return true
    },
    [feedModalPost, postsById, showPopup, user]
  )

  const selectedPost = useMemo(() => {
    if (!selectedPostId) return null
    if (feedModalPost && String(feedModalPost.id) === selectedPostId) {
      return feedModalPost
    }
    return postsById.get(selectedPostId) ?? null
  }, [feedModalPost, selectedPostId, postsById])

  const sharePost = useMemo(() => {
    if (!sharePostId) return null
    if (feedModalPost && String(feedModalPost.id) === sharePostId) {
      return feedModalPost
    }
    return postsById.get(sharePostId) ?? null
  }, [feedModalPost, sharePostId, postsById])

  const selectedPostComments = useMemo(() => {
    if (!selectedPostId) return EMPTY_COMMENTS
    return commentsByPost[selectedPostId] ?? EMPTY_COMMENTS
  }, [selectedPostId, commentsByPost])

  const selectedPostLikeMeta = useMemo(() => {
    if (!selectedPostId) return EMPTY_LIKE_META
    return likesByPost[selectedPostId] ?? EMPTY_LIKE_META
  }, [selectedPostId, likesByPost])

  const selectedPostCommentSubmitting = useMemo(() => {
    if (!selectedPostId) return false
    return !!commentSubmitting[selectedPostId]
  }, [selectedPostId, commentSubmitting])

  useEffect(() => {
    const target = parseFeedDeepLinkTarget(searchParams)
    if (!target || !user?.id) return

    const key = feedDeepLinkSessionKey(target)
    if (feedDeepLinkHandledRef.current === key) return

    void (async () => {
      const row = await fetchFeedDeepLinkContent(supabase, target)
      if (!row) return

      const { enriched, likesMap, commentCountsMap } =
        await loadEngagementForPosts(
        [row],
        { id: user.id }
      )
      const post = enriched[0]
      if (!post) return

      feedDeepLinkHandledRef.current = key
      setFeedModalPost(post)
      setSelectedPostId(String(post.id))
      setLikesByPost((prev) => ({ ...prev, ...likesMap }))
      commentCountsByPostRef.current = {
        ...commentCountsByPostRef.current,
        ...commentCountsMap,
      }
      setCommentCountsByPost(commentCountsByPostRef.current)
      void loadCommentsForPost(post)
      if (target.openComments) {
        openCommentsRef.current[String(post.id)] = true
      }
    })()
  }, [
    searchParams,
    user?.id,
    loadEngagementForPosts,
    loadCommentsForPost,
  ])

  const handleNativePullToRefresh = useCallback(async () => {
    bumpFeedRequestGeneration()
    pageRef.current = 0
    hasMoreRef.current = true
    loadingRef.current = false
    setPage(0)
    setHasMore(true)
    setFeedLoadError(null)
    await loadPosts(0)
  }, [bumpFeedRequestGeneration, loadPosts])

  return (
    <NativeIosPullToRefresh onRefresh={handleNativePullToRefresh}>
    <div className="w-full text-white">
      <h1 className="sr-only">Feed</h1>
      {feedbackModalProps.isOpen ? (
        <FeedbackModal {...feedbackModalProps} />
      ) : null}
      {deleteReelConfirmProps.open ? (
        <ConfirmModal {...deleteReelConfirmProps} />
      ) : null}
      <div className="flex justify-center px-4 py-6 sm:py-8 pb-10">
        <div className="w-full max-w-xl space-y-6">
          <FeedModeToggle mode={mode} onModeChange={handleFeedModeChange} />
          <FeedContentToggle
            contentType={contentType}
            onContentTypeChange={setContentType}
          />

          {mode === "following" && user ? (
            <FeedStoriesBar
              currentUser={currentUserProfile}
              currentUserHasStory={currentUserHasStory}
              users={users}
              onStoryUpload={handleStoryFileSelect}
              onOpenStory={openStory}
            />
          ) : null}

          {!authChecked || (!feedReady && uniquePosts.length === 0) ? (
            <SkeletonFeedPage count={3} />
          ) : feedLoadError && uniquePosts.length === 0 ? (
            <EmptyState
              title="Couldn't Load Feed"
              description={feedLoadError}
              className="py-10"
              action={
                <button
                  type="button"
                  onClick={() => {
                    bumpFeedRequestGeneration()
                    resetFeedState()
                    setFeedLoadError(null)
                    setLoading(true)
                    void loadPosts(0)
                  }}
                  className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600"
                >
                  Retry
                </button>
              }
            />
          ) : feedReady && !loading && uniquePosts.length === 0 ? (
            <EmptyState
              title={
                feedEmptyState === "following_nobody"
                  ? "You're not following anyone yet"
                  : "No posts yet"
              }
              description={
                feedEmptyState === "following_nobody"
                  ? "Follow traders on Explore to see their posts and activity here."
                  : mode === "following"
                    ? contentType === "trades"
                      ? "Trade posts from traders you follow will show up here when they share."
                      : contentType === "posts"
                        ? "Profile posts from traders you follow will show up here when they share."
                        : "Posts from traders you follow will show up here when they share."
                    : contentType === "trades"
                      ? "Public trade posts will show up here as traders share."
                      : contentType === "posts"
                        ? "Public profile posts will show up here as traders share."
                        : "The feed is quiet for now. Check back as traders post updates."
              }
              action={
                feedEmptyState === "following_nobody" ? (
                  <Link
                    href="/explore"
                    className="text-sm font-medium text-blue-300 hover:text-blue-200"
                  >
                    Explore traders →
                  </Link>
                ) : undefined
              }
              className="py-10"
            />
          ) : uniquePosts.length > 0 ? (
            <FeedPostList
              posts={uniquePosts}
              user={user}
              likesByPost={likesByPost}
              likeBusyByPost={likeBusyByPost}
              commentCountsByPost={commentCountsByPost}
              onSelectPost={handleSelectPost}
              onOpenComments={handleOpenPostComments}
              onOpenLinkedTrade={handleOpenLinkedTrade}
              onOpenAttachedReel={handleOpenAttachedReel}
              onToggleLike={toggleLike}
              onSharePost={handleSharePost}
              openReelMenuId={openReelMenuId}
              onReelMenuToggle={handleReelMenuToggle}
              onEditReel={handleStartEditReel}
              onDeleteReel={requestDeleteReel}
              onReplaceReelVideo={handleReplaceReelVideo}
            />
          ) : null}

          <FeedLoadMoreFooter
            loading={loading}
            hasMore={hasMore}
            onLoadMore={loadPosts}
          />
        </div>
      </div>

      {activeStoryUser && currentStory ? (
        <FeedStoryViewer
          activeStoryUser={activeStoryUser}
          users={users}
          storiesByUser={storiesByUser}
          currentStories={currentStories}
          currentStoryIndex={currentStoryIndex}
          currentStory={currentStory}
          currentUserId={user?.id}
          canGoPrevSlide={storyNavigation.canGoPrevSlide}
          canGoNextSlide={storyNavigation.canGoNextSlide}
          canGoPrevUser={storyNavigation.canGoPrevUser}
          canGoNextUser={storyNavigation.canGoNextUser}
          onClose={handleCloseStoryViewer}
          onPrevSlide={prevSlide}
          onNextSlide={nextSlide}
          onPrevUser={prevUser}
          onNextUser={nextUser}
          onStoryReplyError={(message) =>
            showPopup({ type: "error", message })
          }
        />
      ) : null}

      {selectedPostId || sharePostId || stackedAttachedReel ? (
        <FeedPostOverlays
          selectedPostId={selectedPostId}
          selectedPost={selectedPost}
          sharePostId={sharePostId}
          sharePost={sharePost}
          user={user}
          selectedPostComments={selectedPostComments}
          selectedPostCommentCount={
            selectedPostId ? commentCountsByPost[selectedPostId] ?? 0 : 0
          }
          selectedPostLikeMeta={selectedPostLikeMeta}
          selectedPostLikeBusy={
            selectedPostId ? !!likeBusyByPost[selectedPostId] : false
          }
          selectedPostCommentSubmitting={selectedPostCommentSubmitting}
          draftSyncRef={draftSyncRef}
          openCommentsRef={openCommentsRef}
          openTradeRef={openTradeRef}
          tradeExpandSignal={tradeExpandSignal}
          stackedAttachedReel={stackedAttachedReel}
          stackedAttachedReelComments={
            stackedAttachedReel
              ? commentsByPost[String(stackedAttachedReel.id)] ?? EMPTY_COMMENTS
              : EMPTY_COMMENTS
          }
          stackedAttachedReelCommentCount={
            stackedAttachedReel
              ? commentCountsByPost[String(stackedAttachedReel.id)] ?? 0
              : 0
          }
          stackedAttachedReelLikeMeta={
            stackedAttachedReel
              ? likesByPost[String(stackedAttachedReel.id)] ?? EMPTY_LIKE_META
              : EMPTY_LIKE_META
          }
          stackedAttachedReelLikeBusy={
            stackedAttachedReel
              ? !!likeBusyByPost[String(stackedAttachedReel.id)]
              : false
          }
          stackedAttachedReelCommentSubmitting={
            stackedAttachedReel
              ? !!commentSubmitting[String(stackedAttachedReel.id)]
              : false
          }
          onCloseStackedAttachedReel={handleCloseStackedAttachedReel}
          onCloseDetailModal={handleCloseDetailModal}
          onCloseShareOverlay={handleCloseShareOverlay}
          onToggleLike={toggleLike}
          onSubmitComment={submitComment}
          onDeleteComment={deleteComment}
          onTogglePinComment={togglePinComment}
          onSharePost={handleSharePost}
          openReelMenuId={openReelMenuId}
          onReelMenuToggle={handleReelMenuToggle}
          onEditReel={handleStartEditReel}
          onDeleteReel={requestDeleteReel}
          onReplaceReelVideo={handleReplaceReelVideo}
          onOpenAttachedReel={handleOpenAttachedReel}
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

      {editingReel ? (
        <ReelComposerModal
          open
          userId={user?.id ?? null}
          editReel={editingReel}
          onClose={() => setEditingReel(null)}
          onSaved={handleReelSaved}
        />
      ) : null}

      {storyComposeOpen ? (
        <StoryComposeModal
          open
          posting={postingStory}
          profile={currentUserProfile}
          previewUrl={pendingStoryPreviewUrl}
          onClose={closeStoryCompose}
          onPost={() => void handlePostStory()}
          onReplaceImage={(file) => void setStoryDraft(file)}
        />
      ) : null}
    </div>
    </NativeIosPullToRefresh>
  )
}
