"use client"

import type { ReactNode } from "react"
import EmptyState from "@/app/components/ui/EmptyState"
import ProfileCreateMenu from "./ProfileCreateMenu"
import ProfilePrivateTabMessage from "./ProfilePrivateTabMessage"
import type { ProfileWallPostRow } from "./profileTypes"

type ProfilePostsTabProps = {
  posts: ProfileWallPostRow[]
  ready: boolean
  isOwnProfile: boolean
  canView: boolean
  onCreateStory: () => void
  onCreatePost: () => void
  onCreateReel: () => void
  onCreateQuickTrade: () => void
  renderPost: (post: ProfileWallPostRow) => ReactNode
}

export default function ProfilePostsTab({
  posts,
  ready,
  isOwnProfile,
  canView,
  onCreateStory,
  onCreatePost,
  onCreateReel,
  onCreateQuickTrade,
  renderPost,
}: ProfilePostsTabProps) {
  return (
    <div className="mt-4 w-full pb-8">
      {!ready ? (
        <div className="grid grid-cols-1 gap-6 md:grid-cols-2">
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
        <div className="grid grid-cols-1 gap-x-6 gap-y-8 md:grid-cols-2">
          {posts.map((post) => (
            <div key={post.id} id={`post-${post.id}`}>
              {renderPost(post)}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
