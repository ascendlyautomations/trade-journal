"use client"

import { useCallback, useEffect, useRef, useState, type ReactNode } from "react"
import FeedPostCard, {
  EMPTY_COMMENTS,
  EMPTY_LIKE_META,
  type FeedLikeMeta,
} from "@/app/components/feed/FeedPostCard"
import FeedPostDetailModal from "@/app/components/feed/FeedPostDetailModal"
import { queryFeedComments } from "@/app/components/feed/feedPostHelpers"
import type { FeedItem } from "@/app/components/feed/feedPostHelpers"
import {
  fetchFeaturedTradesWeek,
  type FeaturedTradesWeekResponse,
} from "@/lib/featuredTradesWeek"
import {
  LANDING_CARD_FULL,
  LANDING_HEADLINE_SM,
  LANDING_LEAD,
  LANDING_LEAD_GAP,
  LANDING_SECTION_BORDER,
  LANDING_SECTION_CONTENT_GAP,
  LANDING_SECTION_SHELL,
  LANDING_SECTION_SPACING,
} from "@/lib/landingPageUi"
import { supabase } from "@/lib/supabaseClient"
import { useUserProfile } from "@/lib/useUserProfile"

type FeaturedSlot = {
  key: "bestPnl" | "highestRr"
  label: string
  description: string
  badge: string
  badgeClassName: string
  post: FeedItem | null
}

const SLOTS: Omit<FeaturedSlot, "post">[] = [
  {
    key: "bestPnl",
    label: "🏆 Best Trade of the Week",
    description:
      "The community's top-performing trade based on overall performance.",
    badge: "🏆 Best Trade",
    badgeClassName:
      "border-amber-400/35 bg-amber-500/20 text-amber-100",
  },
  {
    key: "highestRr",
    label: "📈 Highest Risk:Reward Trade",
    description: "The highest R:R trade shared with the community this week.",
    badge: "📈 Highest R:R",
    badgeClassName:
      "border-emerald-400/35 bg-emerald-500/20 text-emerald-100",
  },
]

function FeaturedTradePlaceholder() {
  return (
    <div
      className={`${LANDING_CARD_FULL} flex min-h-[280px] flex-col items-center justify-center px-6 py-10 text-center md:min-h-[320px]`}
    >
      <p className="text-base font-medium text-gray-300">
        No featured trades yet this week.
      </p>
      <p className="mt-2 max-w-sm text-sm leading-relaxed text-gray-500">
        Log great trades and yours could be featured next.
      </p>
    </div>
  )
}

function FeaturedTradeCardShell({
  label,
  description,
  badge,
  badgeClassName,
  children,
}: {
  label: string
  description: string
  badge: string
  badgeClassName: string
  children: ReactNode
}) {
  return (
    <div className="flex h-full flex-col">
      <div className="mb-4 text-center md:mb-5 md:text-left">
        <h3 className="text-base font-semibold text-white md:text-lg">{label}</h3>
        <p className="mt-1.5 text-sm leading-relaxed text-gray-400">{description}</p>
      </div>
      <div className="relative flex-1">
        <span
          className={`pointer-events-none absolute right-3 top-3 z-10 rounded-full border px-2.5 py-1 text-[10px] font-semibold uppercase tracking-wide shadow-sm ${badgeClassName}`}
        >
          {badge}
        </span>
        {children}
      </div>
    </div>
  )
}

async function loadTradePostEngagement(
  postId: string,
  userId: string | null
): Promise<{ likeMeta: FeedLikeMeta; comments: any[] }> {
  const [{ data: likesRows }, commentsResult] = await Promise.all([
    supabase.from("likes").select("post_id, user_id").eq("post_id", postId),
    queryFeedComments((select) =>
      supabase
        .from("comments")
        .select(select)
        .eq("post_id", postId)
        .order("created_at", { ascending: true })
    ),
  ])

  const likeMeta: FeedLikeMeta = { count: 0, liked: false }
  for (const row of likesRows ?? []) {
    likeMeta.count += 1
    if (userId && row.user_id === userId) likeMeta.liked = true
  }

  return {
    likeMeta,
    comments: (commentsResult.data as any[]) ?? [],
  }
}

export default function LandingFeaturedTradesSection() {
  const { user } = useUserProfile()
  const [featured, setFeatured] = useState<FeaturedTradesWeekResponse>({
    bestPnlPost: null,
    highestRrPost: null,
  })
  const [loaded, setLoaded] = useState(false)
  const [selectedPost, setSelectedPost] = useState<FeedItem | null>(null)
  const [likeMeta, setLikeMeta] = useState<FeedLikeMeta>(EMPTY_LIKE_META)
  const [comments, setComments] = useState<any[]>(EMPTY_COMMENTS)
  const [commentSubmitting, setCommentSubmitting] = useState(false)
  const draftSyncRef = useRef<Record<string, string>>({})
  const openCommentsRef = useRef<Record<string, boolean>>({})

  useEffect(() => {
    let cancelled = false
    void (async () => {
      const data = await fetchFeaturedTradesWeek()
      if (!cancelled) {
        setFeatured(data)
        setLoaded(true)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [])

  const slots: FeaturedSlot[] = SLOTS.map((slot) => ({
    ...slot,
    post:
      slot.key === "bestPnl"
        ? featured.bestPnlPost
        : featured.highestRrPost,
  }))

  const hasAnyFeatured = slots.some((slot) => slot.post != null)

  const handleSelectPost = useCallback(
    (post: FeedItem) => {
      setSelectedPost(post)
      setLikeMeta(EMPTY_LIKE_META)
      setComments(EMPTY_COMMENTS)
      void loadTradePostEngagement(String(post.id), user?.id ?? null).then(
        ({ likeMeta: nextLikeMeta, comments: nextComments }) => {
          setLikeMeta(nextLikeMeta)
          setComments(nextComments)
        }
      )
    },
    [user?.id]
  )

  const handleCloseModal = useCallback(() => {
    setSelectedPost(null)
  }, [])

  const handleToggleLike = useCallback(
    async (post: FeedItem) => {
      if (!user?.id) return
      const pid = String(post.id)
      const current = likeMeta
      if (current.liked) {
        await supabase.from("likes").delete().eq("post_id", pid).eq("user_id", user.id)
        setLikeMeta({
          count: Math.max(0, current.count - 1),
          liked: false,
        })
        return
      }
      const { error } = await supabase
        .from("likes")
        .insert({ post_id: pid, user_id: user.id })
      if (!error) {
        setLikeMeta({
          count: current.count + 1,
          liked: true,
        })
      }
    },
    [likeMeta, user?.id]
  )

  const handleSubmitComment = useCallback(
    async (post: FeedItem, text: string) => {
      if (!user?.id || !text.trim()) return false
      setCommentSubmitting(true)
      const pid = String(post.id)
      const { data, error } = await supabase
        .from("comments")
        .insert({
          post_id: pid,
          user_id: user.id,
          content: text.trim(),
        })
        .select()
        .single()
      setCommentSubmitting(false)
      if (error || !data) return false
      setComments((prev) => [...prev, data])
      return true
    },
    [user?.id]
  )

  return (
    <>
      <section
        id="featured-trades"
        className={`relative z-10 ${LANDING_SECTION_BORDER} ${LANDING_SECTION_SPACING}`}
        aria-labelledby="featured-trades-heading"
      >
        <div className={LANDING_SECTION_SHELL}>
          <div className="mx-auto max-w-3xl text-center">
            <h2 id="featured-trades-heading" className={LANDING_HEADLINE_SM}>
              🏆 Featured Trades of the Week
            </h2>
            <p className={`${LANDING_LEAD} mx-auto ${LANDING_LEAD_GAP}`}>
              Discover some of the community&apos;s best trades from this week.
            </p>
          </div>

          <div
            className={`${LANDING_SECTION_CONTENT_GAP} grid gap-6 md:grid-cols-2 md:gap-8`}
          >
            {hasAnyFeatured || !loaded ? (
              slots.map((slot) => (
                <FeaturedTradeCardShell
                  key={slot.key}
                  label={slot.label}
                  description={slot.description}
                  badge={slot.badge}
                  badgeClassName={slot.badgeClassName}
                >
                  {slot.post ? (
                    <FeedPostCard
                      post={slot.post}
                      user={user}
                      likeMeta={EMPTY_LIKE_META}
                      comments={EMPTY_COMMENTS}
                      commentSubmitting={false}
                      onSelectPost={handleSelectPost}
                      onOpenComments={handleSelectPost}
                      onToggleLike={() => {}}
                      onSubmitComment={async () => false}
                      onSharePost={() => {}}
                    />
                  ) : loaded ? (
                    <FeaturedTradePlaceholder />
                  ) : (
                    <div
                      className={`${LANDING_CARD_FULL} min-h-[280px] animate-pulse md:min-h-[320px]`}
                      aria-hidden
                    />
                  )}
                </FeaturedTradeCardShell>
              ))
            ) : (
              <div className="md:col-span-2">
                <FeaturedTradePlaceholder />
              </div>
            )}
          </div>
        </div>
      </section>

      {selectedPost ? (
        <FeedPostDetailModal
          post={selectedPost}
          user={user}
          comments={comments}
          likeMeta={likeMeta}
          commentSubmitting={commentSubmitting}
          draftSyncRef={draftSyncRef}
          openCommentsRef={openCommentsRef}
          onClose={handleCloseModal}
          onToggleLike={handleToggleLike}
          onSubmitComment={handleSubmitComment}
          onSharePost={() => {}}
        />
      ) : null}
    </>
  )
}
