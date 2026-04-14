"use client"

type LikeMeta = {
  count: number
  liked: boolean
}

type PostInteractionsProps = {
  post: any
  user: any
  comments: any[]
  likeMeta: LikeMeta
  commentsOpen: boolean
  commentValue: string
  commentSubmitting: boolean
  onToggleLike: (post: any) => void
  onToggleComments: (postId: string) => void
  onCommentChange: (postId: string, value: string) => void
  onSubmitComment: (post: any) => void
  onSharePost?: (post: any) => void
  stopPropagation?: boolean
}

export default function PostInteractions({
  post,
  user,
  comments,
  likeMeta,
  commentsOpen,
  commentValue,
  commentSubmitting,
  onToggleLike,
  onToggleComments,
  onCommentChange,
  onSubmitComment,
  onSharePost,
  stopPropagation = false,
}: PostInteractionsProps) {
  const pid = String(post.id)
  const guardProps = stopPropagation
    ? {
        onClick: (e: React.MouseEvent) => e.stopPropagation(),
        onKeyDown: (e: React.KeyboardEvent) => e.stopPropagation(),
      }
    : {}

  return (
    <div
      className="flex flex-col gap-2 pt-1 border-t border-white/5"
      {...guardProps}
    >
      <div className="flex items-center gap-4">
        <button
          type="button"
          onClick={(e) => {
            if (stopPropagation) e.stopPropagation()
            onToggleLike(post)
          }}
          disabled={!user}
          className="flex items-center gap-1.5 text-sm text-gray-400 hover:text-gray-200 disabled:opacity-50"
          aria-label={likeMeta.liked ? "Unlike" : "Like"}
        >
          <span className="text-lg leading-none" aria-hidden>
            {likeMeta.liked ? "❤️" : "🤍"}
          </span>
          <span className="tabular-nums">{likeMeta.count}</span>
        </button>
        {onSharePost ? (
          <button
            type="button"
            onClick={(e) => {
              if (stopPropagation) e.stopPropagation()
              onSharePost(post)
            }}
            className="text-gray-400 hover:text-white"
            aria-label="Share post"
          >
            📤
          </button>
        ) : null}
      </div>

      <button
        type="button"
        onClick={(e) => {
          if (stopPropagation) e.stopPropagation()
          onToggleComments(pid)
        }}
        className="text-left text-sm text-gray-400 hover:text-gray-200"
      >
        {commentsOpen ? "Hide comments" : `View comments (${comments.length})`}
      </button>

      {commentsOpen ? (
        <div className="mt-3 space-y-2">
          {comments.map((c: any) => {
            return (
              <div key={c.id} className="flex gap-2 items-start">
                <img
                  src={c.profiles?.avatar_url || "/default-avatar.png"}
                  className="w-8 h-8 rounded-full object-cover shrink-0"
                  alt="avatar"
                />
                <div className="min-w-0">
                  <p className="text-xs text-gray-400">
                    {c.profiles?.username || "User"}
                  </p>
                  <p className="text-white text-sm break-words">{c.content}</p>
                </div>
              </div>
            )
          })}

          {user ? (
            <div
              className="flex gap-2 mt-2"
              onClick={(e) => {
                if (stopPropagation) e.stopPropagation()
              }}
              onKeyDown={(e) => {
                if (stopPropagation) e.stopPropagation()
              }}
            >
              <input
                id={`comment-input-${pid}`}
                type="text"
                placeholder="Add a comment…"
                value={commentValue}
                onChange={(e) => onCommentChange(pid, e.target.value)}
                onClick={(e) => {
                  if (stopPropagation) e.stopPropagation()
                }}
                onFocus={(e) => {
                  if (stopPropagation) e.stopPropagation()
                }}
                onKeyDown={(e) => {
                  if (stopPropagation) e.stopPropagation()
                  if (e.key === "Enter" && !e.shiftKey) {
                    e.preventDefault()
                    onSubmitComment(post)
                  }
                }}
                className="flex-1 min-w-0 p-2 bg-[#1e293b] text-white rounded-lg border border-gray-600 text-sm placeholder:text-gray-500"
              />
              <button
                type="button"
                disabled={commentSubmitting || !commentValue.trim()}
                onClick={(e) => {
                  if (stopPropagation) e.stopPropagation()
                  onSubmitComment(post)
                }}
                className="bg-blue-500 px-3 rounded-lg text-white text-sm font-medium disabled:opacity-40 shrink-0"
              >
                {commentSubmitting ? "…" : "Post"}
              </button>
            </div>
          ) : null}
        </div>
      ) : null}
    </div>
  )
}
