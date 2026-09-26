"use client"

import { useEffect, useRef, useState, type ReactNode } from "react"
import EmptyState from "@/app/components/ui/EmptyState"
import ProfileCreateMenu from "./ProfileCreateMenu"
import ProfilePrivateTabMessage from "./ProfilePrivateTabMessage"
import type { ProfileWallPostRow } from "./profileTypes"

type ProfilePostsTabProps = {
  posts: ProfileWallPostRow[]
  ready: boolean
  isOwnProfile: boolean
  canView: boolean
  hasMore?: boolean
  loadingMore?: boolean
  onLoadMore?: () => void
  onCreateStory: () => void
  onCreatePost: () => void
  onCreateReel: () => void
  onCreateQuickTrade: () => void
  renderPost: (post: ProfileWallPostRow) => ReactNode
}

function getAppScrollRoot(): Element | null {
  if (typeof document === "undefined") return null
  const el = document.querySelector("[data-tt-app-scroll]")
  return el instanceof HTMLElement ? el : null
}

export default function ProfilePostsTab({
  posts,
  ready,
  isOwnProfile,
  canView,
  hasMore = false,
  loadingMore = false,
  onLoadMore,
  onCreateStory,
  onCreatePost,
  onCreateReel,
  onCreateQuickTrade,
  renderPost,
}: ProfilePostsTabProps) {
  const [isMobile, setIsMobile] = useState(false)
  const sentinelRef = useRef<HTMLDivElement>(null)
  const loadingRef = useRef(loadingMore)
  const hasMoreRef = useRef(hasMore)
  loadingRef.current = loadingMore
  hasMoreRef.current = hasMore

  useEffect(() => {
    const mq = window.matchMedia("(max-width: 767px)")
    const sync = () => setIsMobile(mq.matches)
    sync()
    mq.addEventListener("change", sync)
    return () => mq.removeEventListener("change", sync)
  }, [])

  useEffect(() => {
    if (!isMobile || !canView || !hasMore || !onLoadMore) return
    const sentinel = sentinelRef.current
    if (!sentinel) return

    const observer = new IntersectionObserver(
      (entries) => {
        if (!entries.some((entry) => entry.isIntersecting)) return
        if (loadingRef.current || !hasMoreRef.current) return
        onLoadMore()
      },
      { root: getAppScrollRoot(), rootMargin: "0px", threshold: 0 }
    )

    observer.observe(sentinel)
    return () => observer.disconnect()
  }, [canView, hasMore, isMobile, onLoadMore, posts.length])

  return (
    <div className="mt-1 w-full pb-8 sm:mt-4">
      {!ready ? (
        <div className="tt-profile-browse-grid tt-profile-post-grid grid grid-cols-1 gap-6 md:grid-cols-2">
          {Array.from({ length: 2 }).map((_, i) => (
            <div
              key={i}
              className="h-56 animate-pulse rounded-xl border border-white/10 bg-white/5"
            />
          ))}
        </div>
      ) : posts.length === 0 ? (
        isOwnProfile ? (
          <EmptyState
            title="No Posts Yet"
            description="Share trades and updates with the community."
            action={
              <ProfileCreateMenu
                variant="link"
                onCreateStory={onCreateStory}
                onCreatePost={onCreatePost}
                onCreateReel={onCreateReel}
                onCreateQuickTrade={onCreateQuickTrade}
              />
            }
            className="py-10"
          />
        ) : !canView ? (
          <ProfilePrivateTabMessage variant="posts" />
        ) : (
          <p className="text-center text-sm text-gray-400">No posts yet.</p>
        )
      ) : (
        <div className="tt-profile-browse-grid tt-profile-post-grid grid grid-cols-1 gap-x-6 gap-y-4 md:grid-cols-2 md:gap-y-8">
          {posts.map((post) => (
            <div key={post.id} id={`post-${post.id}`}>
              {renderPost(post)}
            </div>
          ))}
        </div>
      )}

      {isMobile && hasMore && canView ? (
        <div ref={sentinelRef} className="h-1 w-full shrink-0" aria-hidden />
      ) : null}

      {!isMobile && hasMore && canView && onLoadMore ? (
        <button
          type="button"
          onClick={onLoadMore}
          disabled={loadingMore}
          className="mt-4 w-full rounded bg-white/10 py-2 hover:bg-white/20"
        >
          Load More
        </button>
      ) : null}
    </div>
  )
}
