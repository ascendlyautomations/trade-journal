"use client"

import type { ChangeEvent } from "react"
import Link from "next/link"
import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react"
import { useSearchParams } from "next/navigation"
import { supabase } from "../../../lib/supabaseClient"
import { isUserPro, reachedMessagesCommentsLimit } from "@/lib/freePlanLimits"
import { feedbackPresets } from "@/lib/feedbackPresets"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import {
  deleteFeedComment,
  filterCommentsAfterDelete,
} from "@/lib/deleteComment"
import FeedLoadMoreFooter from "../../components/feed/FeedLoadMoreFooter"
import FeedContentToggle from "../../components/feed/FeedContentToggle"
import FeedModeToggle from "../../components/feed/FeedModeToggle"
import FeedPostList from "../../components/feed/FeedPostList"
import FeedPostOverlays from "../../components/feed/FeedPostOverlays"
import FeedStoriesBar, { type StoryBarProfile } from "../../components/feed/FeedStoriesBar"
import FeedStoryViewer from "../../components/feed/FeedStoryViewer"
import StoryComposeModal from "../../components/feed/StoryComposeModal"
import {
  EMPTY_COMMENTS,
  EMPTY_LIKE_META,
} from "../../components/feed/FeedPostCard"
import {
  FEED_COMMENT_INSERT_SELECT,
  FEED_STORIES_SELECT,
  buildFeedPostsIndex,
  queryFeedComments,
  withInsertedParentCommentId,
  type FeedContentFilter,
  type FeedItem,
} from "../../components/feed/feedPostHelpers"
import {
  FEED_PAGE_SIZE,
  fetchFollowingIds,
  fetchProfileFeedBatch,
  fetchTradeFeedBatch,
  topUpMergedFeedBuffer,
} from "@/lib/feedContent"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import EmptyState from "@/app/components/ui/EmptyState"
import { SkeletonFeedPage } from "@/app/components/ui/skeletons"
import { publishStory } from "@/lib/publishStory"
import {
  createStoryPreviewUrl,
  prepareStoryImageFile,
  revokeStoryPreviewUrl,
} from "@/lib/storyComposeHelpers"
import { useUserProfile } from "@/lib/UserProfileProvider"

const STORY_WINDOW_MS = 24 * 60 * 60 * 1000
/** Auto-advance each slide (Instagram-style). */
const STORY_SLIDE_MS = 7000
const EMPTY_STORY_LIST: StoryRow[] = []

type StoryRow = {
  id: string
  user_id: string
  image_url: string
  created_at: string
}

/** Trade owner for notifications (not always same as post author). */
function postTradeOwnerUserId(post: any): string | null | undefined {
  const t = post?.trades
  const row = t ? (Array.isArray(t) ? t[0] : t) : null
  const fromTrade = row?.user_id
  if (fromTrade != null && String(fromTrade).trim() !== "") return String(fromTrade)
  return post?.user_id ?? null
}

type LikeMeta = { count: number; liked: boolean }

type FeedEmptyState = "following_nobody" | "no_posts"

export default function FeedPage() {
  return (
    <Suspense fallback={<SkeletonFeedPage />}>
      <FeedPageContent />
    </Suspense>
  )
}

function FeedPageContent() {
  const searchParams = useSearchParams()
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const { user, profile, loading: profileLoading } = useUserProfile()
  const authChecked = !profileLoading
  const [posts, setPosts] = useState<any[]>([])
  const [page, setPage] = useState(0)
  const [loading, setLoading] = useState(false)
  const [hasMore, setHasMore] = useState(true)
  const pageRef = useRef(0)
  const loadingRef = useRef(false)
  const hasMoreRef = useRef(true)
  const [mode, setMode] = useState<"global" | "following">("following")
  const [contentType, setContentType] = useState<FeedContentFilter>("all")
  const mergeBufferRef = useRef<FeedItem[]>([])
  const tradePageRef = useRef(0)
  const profilePageRef = useRef(0)
  const tradeExhaustedRef = useRef(false)
  const profileExhaustedRef = useRef(false)
  const [likesByPost, setLikesByPost] = useState<Record<string, LikeMeta>>({})
  const [commentsByPost, setCommentsByPost] = useState<Record<string, any[]>>({})
  const [commentSubmitting, setCommentSubmitting] = useState<Record<string, boolean>>({})
  const [selectedPostId, setSelectedPostId] = useState<string | null>(null)
  const [sharePostId, setSharePostId] = useState<string | null>(null)
  const [storiesByUser, setStoriesByUser] = useState<Record<string, StoryRow[]>>(
    {}
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

  const likesByPostRef = useRef(likesByPost)
  likesByPostRef.current = likesByPost
  const draftSyncRef = useRef<Record<string, string>>({})
  const openCommentsRef = useRef<Record<string, boolean>>({})
  const likeBusyRef = useRef<Set<string>>(new Set())
  const commentSubmittingRef = useRef<Set<string>>(new Set())
  const postingStoryRef = useRef(false)
  const [likeBusyByPost, setLikeBusyByPost] = useState<Record<string, boolean>>({})

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
    () =>
      Boolean(
        user?.id && (storiesByUser[user.id]?.length ?? 0) > 0
      ),
    [user?.id, storiesByUser]
  )

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

  const loadFollowingStories = useCallback(async () => {
    if (!user?.id) return

    setCurrentUserProfile(
      profile
        ? {
            id: profile.id,
            username: profile.username,
            avatar_url: profile.avatar_url,
          }
        : { id: user.id, username: null, avatar_url: null }
    )

    const { data: following } = await supabase
      .from("followers")
      .select("following_id")
      .eq("follower_id", user.id)

    const followingIds = [
      ...new Set(
        (following ?? [])
          .map((f) => f.following_id)
          .filter((id): id is string => id != null && String(id).trim() !== "")
      ),
    ]

    const storyUserIds = [...new Set([...followingIds, user.id])]

    const { data: stories, error: storiesErr } = await supabase
      .from("stories")
      .select(FEED_STORIES_SELECT)
      .in("user_id", storyUserIds)
      .order("created_at", { ascending: false })

    if (storiesErr) {
      console.error("stories fetch:", storiesErr)
      setStoriesByUser({})
      setUsers([])
      return
    }

    const now = Date.now()
    const recentStories = (stories ?? []).filter((story) => {
      const created = new Date(story.created_at).getTime()
      return !Number.isNaN(created) && now - created < STORY_WINDOW_MS
    })

    const storiesByUserMap: Record<string, StoryRow[]> = {}
    for (const story of recentStories) {
      const uid = String(story.user_id)
      if (!storiesByUserMap[uid]) storiesByUserMap[uid] = []
      storiesByUserMap[uid].push(story as StoryRow)
    }

    for (const uid of Object.keys(storiesByUserMap)) {
      storiesByUserMap[uid].sort(
        (a, b) =>
          new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
      )
    }

    const userIds = Object.keys(storiesByUserMap)
    if (userIds.length === 0) {
      setStoriesByUser({})
      setUsers([])
      return
    }

    const { data: profiles, error: profilesErr } = await supabase
      .from("profiles")
      .select("id, username, avatar_url")
      .in("id", userIds)

    if (profilesErr) {
      console.error("story bar profiles:", profilesErr)
      setStoriesByUser(storiesByUserMap)
      setUsers([])
      return
    }

    const list = (profiles ?? []) as StoryBarProfile[]
    const latest = (id: string) =>
      new Date(storiesByUserMap[id][0].created_at).getTime()

    list.sort((a, b) => latest(b.id) - latest(a.id))

    setStoriesByUser(storiesByUserMap)
    setUsers(list)
  }, [user, profile])

  useEffect(() => {
    if (profileLoading) return
    if (!user || mode !== "following") {
      setStoriesByUser({})
      setUsers([])
      setCurrentUserProfile(null)
      setActiveStoryUser(null)
      setCurrentStoryIndex(0)
      return
    }

    void loadFollowingStories()
  }, [profileLoading, user, mode, loadFollowingStories])

  const handlePostStory = useCallback(async () => {
    if (!pendingStoryFile || !user?.id || postingStoryRef.current || postingStory) {
      return
    }
    postingStoryRef.current = true
    setPostingStory(true)

    try {
      const result = await publishStory(supabase, user.id, pendingStoryFile)

      if (!result.ok) {
        showPopup({ type: "error", message: result.message })
        return
      }

      showPopup({ type: "success", message: "Story uploaded!" })
      closeStoryCompose()
      await loadFollowingStories()
    } finally {
      postingStoryRef.current = false
      setPostingStory(false)
    }
  }, [
    pendingStoryFile,
    user?.id,
    postingStory,
    showPopup,
    closeStoryCompose,
    loadFollowingStories,
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

  useEffect(() => {
    if (selectedPostId || activeStoryUser) {
      document.body.style.overflow = "hidden"
      return () => {
        document.body.style.overflow = ""
      }
    }
    document.body.style.overflow = ""
    return undefined
  }, [selectedPostId, activeStoryUser])

  const loadEngagementForPosts = useCallback(async (postList: any[], currentUser: any) => {
    if (!postList.length) {
      return {
        enriched: [] as any[],
        likesMap: {} as Record<string, LikeMeta>,
        commentsMap: {} as Record<string, any[]>,
      }
    }

    const ids = postList.map((p) => p.id)

    const [
      { data: likesRows },
      { data: commentsRows },
      { count: likesExactCount },
    ] = await Promise.all([
      supabase.from("likes").select("post_id, user_id").in("post_id", ids),
      queryFeedComments((select) =>
        supabase
          .from("comments")
          .select(select)
          .in("post_id", ids)
          .order("created_at", { ascending: true })
      ),
      supabase
        .from("likes")
        .select("post_id", { count: "exact", head: true })
        .in("post_id", ids),
    ])
    void likesExactCount

    const likesMap: Record<string, LikeMeta> = {}
    for (const id of ids) {
      const key = String(id)
      likesMap[key] = { count: 0, liked: false }
    }
    for (const row of likesRows || []) {
      const pid = String(row.post_id)
      if (!likesMap[pid]) likesMap[pid] = { count: 0, liked: false }
      likesMap[pid].count++
      if (currentUser && row.user_id === currentUser.id) likesMap[pid].liked = true
    }

    const commentsMap: Record<string, any[]> = {}
    for (const id of ids) {
      commentsMap[String(id)] = []
    }
    for (const c of commentsRows || []) {
      const pid = String(c.post_id)
      if (!commentsMap[pid]) commentsMap[pid] = []
      commentsMap[pid].push(c)
    }

    const enriched = postList.map((p) => {
      const key = String(p.id)
      return {
        ...p,
        likesCount: likesMap[key]?.count ?? 0,
      }
    })
    return { enriched, likesMap, commentsMap }
  }, [])

  const loadPosts = useCallback(
    async (pageOverride?: number) => {
      if (!user || loadingRef.current || !hasMoreRef.current) return

      const currentPage = pageOverride ?? pageRef.current

      setLoading(true)
      loadingRef.current = true

      if (currentPage === 0) {
        setFeedEmptyState(null)
      }

      try {
        const followingIds = await fetchFollowingIds(supabase, user.id)
        let list: FeedItem[] = []

        if (contentType === "all") {
          const toppedUp = await topUpMergedFeedBuffer(supabase, {
            scope: mode,
            userId: user.id,
            followingIds,
            buffer: mergeBufferRef.current,
            tradePage: tradePageRef.current,
            profilePage: profilePageRef.current,
            tradeExhausted: tradeExhaustedRef.current,
            profileExhausted: profileExhaustedRef.current,
            targetSize: FEED_PAGE_SIZE,
            pageSize: FEED_PAGE_SIZE,
          })

          mergeBufferRef.current = toppedUp.buffer
          tradePageRef.current = toppedUp.tradePage
          profilePageRef.current = toppedUp.profilePage
          tradeExhaustedRef.current = toppedUp.tradeExhausted
          profileExhaustedRef.current = toppedUp.profileExhausted

          list = mergeBufferRef.current.splice(0, FEED_PAGE_SIZE)

          if (
            mode === "following" &&
            followingIds.length === 0 &&
            currentPage === 0
          ) {
            hasMoreRef.current = false
            setHasMore(false)
            setFeedEmptyState("following_nobody")
            loadingRef.current = false
            setLoading(false)
            return
          }

          if (
            toppedUp.tradeExhausted &&
            toppedUp.profileExhausted &&
            list.length < FEED_PAGE_SIZE
          ) {
            hasMoreRef.current = false
            setHasMore(false)
          }
        } else if (contentType === "trades") {
          const result = await fetchTradeFeedBatch(supabase, {
            scope: mode,
            userId: user.id,
            followingIds,
            page: currentPage,
            pageSize: FEED_PAGE_SIZE,
          })

          if (result.emptyFollowing && currentPage === 0) {
            hasMoreRef.current = false
            setHasMore(false)
            setFeedEmptyState("following_nobody")
            loadingRef.current = false
            setLoading(false)
            return
          }

          list = result.items

          if (list.length < FEED_PAGE_SIZE) {
            hasMoreRef.current = false
            setHasMore(false)
          }
        } else {
          const result = await fetchProfileFeedBatch(supabase, {
            scope: mode,
            userId: user.id,
            followingIds,
            page: currentPage,
            pageSize: FEED_PAGE_SIZE,
          })

          if (result.emptyFollowing && currentPage === 0) {
            hasMoreRef.current = false
            setHasMore(false)
            setFeedEmptyState("following_nobody")
            loadingRef.current = false
            setLoading(false)
            return
          }

          list = result.items

          if (list.length < FEED_PAGE_SIZE) {
            hasMoreRef.current = false
            setHasMore(false)
          }
        }

        const { enriched, likesMap, commentsMap } = await loadEngagementForPosts(
          list,
          user
        )

        if (currentPage === 0 && list.length === 0) {
          setFeedEmptyState("no_posts")
        }

        setPosts((prev) => [...prev, ...enriched])
        setLikesByPost((prev) => ({ ...prev, ...likesMap }))
        setCommentsByPost((prev) => ({ ...prev, ...commentsMap }))
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
      } finally {
        loadingRef.current = false
        setLoading(false)
      }
    },
    [user, mode, contentType, loadEngagementForPosts]
  )

  const resetFeedState = useCallback(() => {
    setPosts([])
    setLikesByPost({})
    setCommentsByPost({})
    setFeedEmptyState(null)
    setPage(0)
    setHasMore(true)
    pageRef.current = 0
    hasMoreRef.current = true
    loadingRef.current = false
    mergeBufferRef.current = []
    tradePageRef.current = 0
    profilePageRef.current = 0
    tradeExhaustedRef.current = false
    profileExhaustedRef.current = false
  }, [])

  useEffect(() => {
    if (profileLoading) return
    if (!user) return
    resetFeedState()
    setLoading(true)
    void loadPosts(0)
  }, [profileLoading, user, mode, contentType, loadPosts, resetFeedState])

  useEffect(() => {
    const handleScroll = () => {
      if (window.innerHeight + window.scrollY >= document.body.offsetHeight - 200) {
        void loadPosts()
      }
    }

    window.addEventListener("scroll", handleScroll)
    return () => window.removeEventListener("scroll", handleScroll)
  }, [loadPosts])

  const handleSelectPost = useCallback((post: any) => {
    setSelectedPostId(String(post.id))
  }, [])

  const handleOpenPostComments = useCallback((post: any) => {
    const pid = String(post.id)
    openCommentsRef.current[pid] = true
    setSelectedPostId(pid)
  }, [])

  const handleSharePost = useCallback((post: any) => {
    setSharePostId(String(post.id))
  }, [])

  const handleCloseDetailModal = useCallback(() => {
    setSelectedPostId(null)
  }, [])

  const handleCloseShareOverlay = useCallback(() => {
    setSharePostId(null)
  }, [])

  const toggleLike = useCallback(
    async (post: any) => {
      if (!user) return

      const pid = String(post.id)
      if (likeBusyRef.current.has(pid)) return

      likeBusyRef.current.add(pid)
      setLikeBusyByPost((prev) => ({ ...prev, [pid]: true }))

      try {
      const meta = likesByPostRef.current[pid] ?? EMPTY_LIKE_META

      if (meta.liked) {
        const { error } = await supabase
          .from("likes")
          .delete()
          .eq("post_id", pid)
          .eq("user_id", user.id)

        if (error) {
          console.error("Unlike error:", error)
          return
        }

        const newCount = Math.max(0, meta.count - 1)
        setLikesByPost((prev) => ({
          ...prev,
          [pid]: { count: newCount, liked: false },
        }))
      } else {
        const { error } = await supabase.from("likes").insert({
          post_id: pid,
          user_id: user.id,
        })

        if (error) {
          console.error("Like error:", error)
          return
        }

        const newCount = meta.count + 1
        setLikesByPost((prev) => ({
          ...prev,
          [pid]: { count: newCount, liked: true },
        }))

        const notifyUserId = postTradeOwnerUserId(post)
        const tradeId = post.trade_id
        if (notifyUserId && notifyUserId !== user.id) {
          const { error: nErr } = await supabase.from("notifications").insert({
            user_id: notifyUserId,
            sender_id: user.id,
            type: "like",
            post_id: pid,
            trade_id: tradeId ?? null,
          })
          if (nErr) {
            console.error("Notification error:", nErr?.message, nErr)
          } else {
            window.dispatchEvent(new CustomEvent("notification-update"))
            window.dispatchEvent(
              new CustomEvent("tj-unread-notifications-refresh")
            )
          }
        }
      }
      } finally {
        likeBusyRef.current.delete(pid)
        setLikeBusyByPost((prev) => ({ ...prev, [pid]: false }))
      }
    },
    [user]
  )

  const submitComment = useCallback(
    async (post: any, text: string, parentCommentId?: string | null) => {
      if (!user) return false

      const pid = String(post.id)
      const trimmed = (text || "").trim()
      if (!trimmed) return false
      if (commentSubmittingRef.current.has(pid)) return false

      commentSubmittingRef.current.add(pid)
      setCommentSubmitting((s) => ({ ...s, [pid]: true }))

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
          return false
        }
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
        console.error("Comment insert error:", error)
        showPopup({ type: "error", message: handleSupabaseError(error) })
        return false
      }

      const insertedRow = withInsertedParentCommentId(newRow, parentCommentId)

      setCommentsByPost((prev) => {
        const currentComments = prev[pid] ?? EMPTY_COMMENTS
        const nextComments = currentComments.some((c: any) => c.id === insertedRow.id)
          ? currentComments
          : [...currentComments, insertedRow]
        return {
          ...prev,
          [pid]: nextComments,
        }
      })

      const notifyUserId = postTradeOwnerUserId(post)
      const tradeId = post.trade_id
      if (notifyUserId && notifyUserId !== user.id) {
        const { error: nErr } = await supabase.from("notifications").insert({
          user_id: notifyUserId,
          sender_id: user.id,
          type: "comment",
          post_id: pid,
          trade_id: tradeId ?? null,
          content: trimmed.slice(0, 200),
        })
        if (nErr) {
          console.error("Notification error:", nErr?.message, nErr)
        } else {
          window.dispatchEvent(new CustomEvent("notification-update"))
          window.dispatchEvent(
            new CustomEvent("tj-unread-notifications-refresh")
          )
        }
      }

      return true
      } finally {
        commentSubmittingRef.current.delete(pid)
        setCommentSubmitting((s) => ({ ...s, [pid]: false }))
      }
    },
    [user, showPopup]
  )

  const deleteComment = useCallback(
    async (comment: any) => {
      if (!user) {
        console.warn("[comment-delete] aborted: no user")
        return false
      }

      const postId = String(comment.post_id ?? "")
      if (!postId) {
        console.error("[comment-delete] aborted: missing post_id", comment)
        return false
      }

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
        showPopup({ type: "error", message: handleSupabaseError(error) })
        return false
      }

      setCommentsByPost((prev) => ({
        ...prev,
        [postId]: filterCommentsAfterDelete(
          prev[postId] ?? EMPTY_COMMENTS,
          String(comment.id)
        ),
      }))

      console.log("[comment-delete] local state updated", {
        commentId: String(comment.id),
        postId,
      })

      return true
    },
    [user, showPopup]
  )

  const { uniquePosts, postsById } = useMemo(
    () => buildFeedPostsIndex(posts),
    [posts]
  )

  const selectedPost = useMemo(
    () => (selectedPostId ? postsById.get(selectedPostId) ?? null : null),
    [selectedPostId, postsById]
  )

  const sharePost = useMemo(
    () => (sharePostId ? postsById.get(sharePostId) ?? null : null),
    [sharePostId, postsById]
  )

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
    const postId = searchParams.get("post")?.trim()
    if (!postId || posts.length === 0) return
    if (postsById.has(postId)) {
      setSelectedPostId(postId)
    }
  }, [searchParams, posts.length, postsById])

  return (
    <div className="w-full text-white">
      <FeedbackModal {...feedbackModalProps} />
      <div className="flex justify-center px-4 py-6 sm:py-8 pb-10">
        <div className="w-full max-w-xl space-y-6">
          <FeedModeToggle mode={mode} onModeChange={setMode} />
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

          {!authChecked || (loading && uniquePosts.length === 0) ? (
            <SkeletonFeedPage count={3} />
          ) : !loading && uniquePosts.length === 0 && feedEmptyState ? (
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
              commentsByPost={commentsByPost}
              commentSubmitting={commentSubmitting}
              draftSyncRef={draftSyncRef}
              onSelectPost={handleSelectPost}
              onOpenComments={handleOpenPostComments}
              onToggleLike={toggleLike}
              onSubmitComment={submitComment}
              onSharePost={handleSharePost}
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
          canGoPrevSlide={storyNavigation.canGoPrevSlide}
          canGoNextSlide={storyNavigation.canGoNextSlide}
          canGoPrevUser={storyNavigation.canGoPrevUser}
          canGoNextUser={storyNavigation.canGoNextUser}
          onClose={handleCloseStoryViewer}
          onPrevSlide={prevSlide}
          onNextSlide={nextSlide}
          onPrevUser={prevUser}
          onNextUser={nextUser}
        />
      ) : null}

      {selectedPostId || sharePostId ? (
        <FeedPostOverlays
          selectedPostId={selectedPostId}
          selectedPost={selectedPost}
          sharePostId={sharePostId}
          sharePost={sharePost}
          user={user}
          selectedPostComments={selectedPostComments}
          selectedPostLikeMeta={selectedPostLikeMeta}
          selectedPostLikeBusy={
            selectedPostId ? !!likeBusyByPost[selectedPostId] : false
          }
          selectedPostCommentSubmitting={selectedPostCommentSubmitting}
          draftSyncRef={draftSyncRef}
          openCommentsRef={openCommentsRef}
          onCloseDetailModal={handleCloseDetailModal}
          onCloseShareOverlay={handleCloseShareOverlay}
          onToggleLike={toggleLike}
          onSubmitComment={submitComment}
          onDeleteComment={deleteComment}
          onSharePost={handleSharePost}
        />
      ) : null}

      <StoryComposeModal
        open={storyComposeOpen}
        posting={postingStory}
        profile={currentUserProfile}
        previewUrl={pendingStoryPreviewUrl}
        onClose={closeStoryCompose}
        onPost={() => void handlePostStory()}
        onReplaceImage={(file) => void setStoryDraft(file)}
      />
    </div>
  )
}
