"use client"

import FeedPostCard, {
  EMPTY_COMMENTS,
  EMPTY_LIKE_META,
} from "@/app/components/feed/FeedPostCard"

type CommunitySharePreviewPanelProps = {
  post: Record<string, unknown> | null
  user: { id: string } | null
  className?: string
  showHeading?: boolean
}

export default function CommunitySharePreviewPanel({
  post,
  user,
  className = "",
  showHeading = true,
}: CommunitySharePreviewPanelProps) {
  if (!post || !user) return null

  return (
    <div className={className}>
      {showHeading ? (
        <p className="mb-2 text-sm text-gray-400">Display Preview</p>
      ) : null}
      <FeedPostCard
        post={post}
        user={user}
        likeMeta={EMPTY_LIKE_META}
        comments={EMPTY_COMMENTS}
        commentSubmitting={false}
        preview
        onSelectPost={() => {}}
        onOpenComments={() => {}}
        onToggleLike={() => {}}
        onSubmitComment={async () => false}
        onSharePost={() => {}}
      />
    </div>
  )
}
