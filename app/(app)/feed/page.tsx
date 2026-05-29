"use client"

import type { ChangeEvent } from "react"
import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { supabase } from "../../../lib/supabaseClient"
import { compressImage } from "@/lib/compressImage"
import { isUserPro, reachedMessagesCommentsLimit } from "@/lib/freePlanLimits"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import FeedLoadMoreFooter from "../../components/feed/FeedLoadMoreFooter"
import FeedModeToggle from "../../components/feed/FeedModeToggle"
import FeedPostList from "../../components/feed/FeedPostList"
import FeedPostOverlays from "../../components/feed/FeedPostOverlays"
import FeedStoriesBar, { type StoryBarProfile } from "../../components/feed/FeedStoriesBar"
import FeedStoryViewer from "../../components/feed/FeedStoryViewer"
import {
  EMPTY_COMMENTS,
  EMPTY_LIKE_META,
} from "../../components/feed/FeedPostCard"
import {
  FEED_COMMENT_INSERT_SELECT,
  FEED_COMMENTS_SELECT,
  FEED_POSTS_SELECT,
  FEED_STORIES_SELECT,
  buildFeedPostsIndex,
} from "../../components/feed/feedPostHelpers"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"

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

export default function FeedPage() {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const [posts, setPosts] = useState<any[]>([])
  const [page, setPage] = useState(0)
  const [loading, setLoading] = useState(false)
  const [hasMore, setHasMore] = useState(true)
  const pageRef = useRef(0)
  const loadingRef = useRef(false)
  const hasMoreRef = useRef(true)
  const [user, setUser] = useState<any>(null)
  const [mode, setMode] = useState<"global" | "following">("following")
  const [likesByPost, setLikesByPost] = useState<Record<string, LikeMeta>>({})
  const [commentsByPost, setCommentsByPost] = useState<Record<string, any[]>>({})
  const [commentSubmitting, setCommentSubmitting] = useState<Record<string, boolean>>({})
  const [selectedPostId, setSelectedPostId] = useState<string | null>(null)
  const [sharePostId, setSharePostId] = useState<string | null>(null)
  const [storiesByUser, setStoriesByUser] = useState<Record<string, StoryRow[]>>(
    {}
  )
  const [users, setUsers] = useState<StoryBarProfile[]>([])
  const [activeStoryUser, setActiveStoryUser] = useState<string | null>(null)
  const [currentStoryIndex, setCurrentStoryIndex] = useState(0)

  const likesByPostRef = useRef(likesByPost)
  likesByPostRef.current = likesByPost
  const draftSyncRef = useRef<Record<string, string>>({})
  const openCommentsRef = useRef<Record<string, boolean>>({})

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

  useEffect(() => {
    fetchUser()
  }, [])

  const loadFollowingStories = useCallback(async () => {
    if (!user?.id) return

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
  }, [user])

  useEffect(() => {
    if (!user || mode !== "following") {
      setStoriesByUser({})
      setUsers([])
      setActiveStoryUser(null)
      setCurrentStoryIndex(0)
      return
    }

    void loadFollowingStories()
  }, [user, mode, loadFollowingStories])

  const handleStoryUpload = useCallback(
    async (e: ChangeEvent<HTMLInputElement>) => {
      const input = e.target
      const file = input.files?.[0]
      input.value = ""
      if (!file || !user?.id) return

      let uploadFile: File = file
      if (file.type?.startsWith("image/")) {
        uploadFile = await compressImage(file)
      }
      const fileName = `${user.id}/${Date.now()}-${uploadFile.name}`

      const { error: uploadError } = await supabase.storage
        .from("stories")
        .upload(fileName, uploadFile, { upsert: true })

      if (uploadError) {
        console.error(uploadError)
        showPopup({ type: "error", message: uploadError.message })
        return
      }

      const base = process.env.NEXT_PUBLIC_SUPABASE_URL
      if (!base) {
        showPopup({ type: "error", message: "Missing NEXT_PUBLIC_SUPABASE_URL" })
        return
      }

      const publicUrl = `${base}/storage/v1/object/public/stories/${fileName}`

      const { error: insertError } = await supabase.from("stories").insert({
        user_id: user.id,
        image_url: publicUrl,
      })

      if (insertError) {
        console.error(insertError)
        showPopup({ type: "error", message: handleSupabaseError(insertError) })
        return
      }

      showPopup({ type: "success", message: "Story uploaded!" })
      await loadFollowingStories()
    },
    [user, loadFollowingStories, showPopup]
  )

  const openStory = useCallback((userId: string) => {
    setActiveStoryUser(userId)
    setCurrentStoryIndex(0)
  }, [])

  const handleCloseStoryViewer = useCallback(() => {
    setActiveStoryUser(null)
    setCurrentStoryIndex(0)
  }, [])

  const nextStory = useCallback(() => {
    const list = activeStoryUser
      ? (storiesByUser[activeStoryUser] ?? [])
      : []

    if (currentStoryIndex < list.length - 1) {
      setCurrentStoryIndex((prev) => prev + 1)
      return
    }

    const userIds = users.map((u) => u.id)
    const currentUserIndex = activeStoryUser
      ? userIds.indexOf(activeStoryUser)
      : -1

    if (currentUserIndex >= 0 && currentUserIndex < userIds.length - 1) {
      const nextUser = userIds[currentUserIndex + 1]
      setActiveStoryUser(nextUser)
      setCurrentStoryIndex(0)
    } else {
      setActiveStoryUser(null)
      setCurrentStoryIndex(0)
    }
  }, [activeStoryUser, currentStoryIndex, storiesByUser, users])

  const prevStory = useCallback(() => {
    const list = activeStoryUser
      ? (storiesByUser[activeStoryUser] ?? [])
      : []

    if (currentStoryIndex > 0) {
      setCurrentStoryIndex((prev) => prev - 1)
      return
    }

    const userIds = users.map((u) => u.id)
    const currentUserIndex = activeStoryUser
      ? userIds.indexOf(activeStoryUser)
      : -1

    if (currentUserIndex > 0) {
      const prevUser = userIds[currentUserIndex - 1]
      const prevUserStories = storiesByUser[prevUser] ?? []

      setActiveStoryUser(prevUser)
      setCurrentStoryIndex(Math.max(0, prevUserStories.length - 1))
    }
  }, [activeStoryUser, currentStoryIndex, storiesByUser, users])

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

    const timer = window.setTimeout(() => {
      nextStory()
    }, STORY_SLIDE_MS)

    return () => clearTimeout(timer)
  }, [activeStoryUser, currentStoryIndex, storiesByUser, nextStory])

  useEffect(() => {
    if (!activeStoryUser) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") {
        setActiveStoryUser(null)
        setCurrentStoryIndex(0)
      }
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [activeStoryUser])

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

  async function fetchUser() {
    const { data } = await supabase.auth.getSession()
    setUser(data.session?.user)
  }

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
      supabase
        .from("comments")
        .select(FEED_COMMENTS_SELECT)
        .in("post_id", ids)
        .order("created_at", { ascending: true }),
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
      const from = currentPage * 8
      const to = from + 7

      setLoading(true)
      loadingRef.current = true

      let list: any[] = []

      if (mode === "global") {
        const { data, error } = await supabase
          .from("posts")
          .select(FEED_POSTS_SELECT)
          .order("created_at", { ascending: false })
          .range(from, to)

        if (error) {
          console.error(error)
          loadingRef.current = false
          setLoading(false)
          return
        }

        list = data || []
      }

      if (mode === "following") {
        const { data: following, error: followingError } = await supabase
          .from("followers")
          .select("following_id")
          .eq("follower_id", user.id)

        if (followingError) {
          console.error(followingError)
          loadingRef.current = false
          setLoading(false)
          return
        }

        const ids = following?.map((f) => f.following_id) || []

        if (ids.length === 0) {
          hasMoreRef.current = false
          setHasMore(false)
          loadingRef.current = false
          setLoading(false)
          return
        }

        const { data, error } = await supabase
          .from("posts")
          .select(FEED_POSTS_SELECT)
          .in("user_id", ids)
          .order("created_at", { ascending: false })
          .range(from, to)

        if (error) {
          console.error(error)
          loadingRef.current = false
          setLoading(false)
          return
        }

        list = data || []
      }

      console.log("FEED TRADE SAMPLE:", list?.[0])

      if (list.length < 8) {
        hasMoreRef.current = false
        setHasMore(false)
      }

      const { enriched, likesMap, commentsMap } = await loadEngagementForPosts(list, user)

      setPosts((prev) => [...prev, ...enriched])
      setLikesByPost((prev) => ({ ...prev, ...likesMap }))
      setCommentsByPost((prev) => ({ ...prev, ...commentsMap }))
      const nextPage = pageOverride != null ? pageOverride + 1 : pageRef.current + 1
      pageRef.current = nextPage
      setPage(nextPage)
      loadingRef.current = false
      setLoading(false)
    },
    [user, mode, loadEngagementForPosts]
  )

  useEffect(() => {
    if (!user) return
    setPosts([])
    setLikesByPost({})
    setCommentsByPost({})
    setPage(0)
    setHasMore(true)
    setLoading(false)
    pageRef.current = 0
    hasMoreRef.current = true
    loadingRef.current = false
    void loadPosts(0)
  }, [user, mode, loadPosts])

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
        if (tradeId && notifyUserId && notifyUserId !== user.id) {
          const { error: nErr } = await supabase.from("notifications").insert({
            user_id: notifyUserId,
            sender_id: user.id,
            type: "like",
            trade_id: tradeId,
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
    },
    [user]
  )

  const submitComment = useCallback(
    async (post: any, text: string) => {
      if (!user) return false

      const pid = String(post.id)
      const trimmed = (text || "").trim()
      if (!trimmed) return false

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
          return false
        }
      }

      setCommentSubmitting((s) => ({ ...s, [pid]: true }))

      const { data: newRow, error } = await supabase
        .from("comments")
        .insert({
          post_id: pid,
          user_id: user.id,
          content: trimmed,
        })
        .select(FEED_COMMENT_INSERT_SELECT)
        .single()

      setCommentSubmitting((s) => ({ ...s, [pid]: false }))

      if (error) {
        console.error("Comment insert error:", error)
        showPopup({ type: "error", message: handleSupabaseError(error) })
        return false
      }

      setCommentsByPost((prev) => {
        const currentComments = prev[pid] ?? EMPTY_COMMENTS
        const nextComments = currentComments.some((c: any) => c.id === newRow.id)
          ? currentComments
          : [...currentComments, newRow]
        return {
          ...prev,
          [pid]: nextComments,
        }
      })

      const notifyUserId = postTradeOwnerUserId(post)
      const tradeId = post.trade_id
      if (tradeId && notifyUserId && notifyUserId !== user.id) {
        const { error: nErr } = await supabase.from("notifications").insert({
          user_id: notifyUserId,
          sender_id: user.id,
          type: "comment",
          trade_id: tradeId,
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

  return (
    <div className="w-full text-white">
      <FeedbackModal {...feedbackModalProps} />
      <div className="flex justify-center px-4 py-6 sm:py-8 pb-10">
        <div className="w-full max-w-xl space-y-6">
          <FeedModeToggle mode={mode} onModeChange={setMode} />

          {mode === "following" && user ? (
            <FeedStoriesBar
              users={users}
              onStoryUpload={handleStoryUpload}
              onOpenStory={openStory}
            />
          ) : null}

          <FeedPostList
            posts={uniquePosts}
            user={user}
            likesByPost={likesByPost}
            commentsByPost={commentsByPost}
            commentSubmitting={commentSubmitting}
            draftSyncRef={draftSyncRef}
            openCommentsRef={openCommentsRef}
            activeDetailPostId={selectedPostId}
            onSelectPost={handleSelectPost}
            onToggleLike={toggleLike}
            onSubmitComment={submitComment}
            onSharePost={handleSharePost}
          />

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
          currentStories={currentStories}
          currentStoryIndex={currentStoryIndex}
          currentStory={currentStory}
          onClose={handleCloseStoryViewer}
          onPrev={prevStory}
          onNext={nextStory}
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
          selectedPostCommentSubmitting={selectedPostCommentSubmitting}
          draftSyncRef={draftSyncRef}
          openCommentsRef={openCommentsRef}
          onCloseDetailModal={handleCloseDetailModal}
          onCloseShareOverlay={handleCloseShareOverlay}
          onToggleLike={toggleLike}
          onSubmitComment={submitComment}
          onSharePost={handleSharePost}
        />
      ) : null}
    </div>
  )
}
