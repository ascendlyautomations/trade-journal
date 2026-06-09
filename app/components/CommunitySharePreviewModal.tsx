"use client"

import { useEffect } from "react"
import FeedPostCard, {
  EMPTY_COMMENTS,
  EMPTY_LIKE_META,
} from "@/app/components/feed/FeedPostCard"

type CommunitySharePreviewModalProps = {
  open: boolean
  onClose: () => void
  onPostTrade: () => void
  submitting?: boolean
  postTradeLabel?: string
  post: Record<string, unknown> | null
  user: { id: string } | null
}

export default function CommunitySharePreviewModal({
  open,
  onClose,
  onPostTrade,
  submitting = false,
  postTradeLabel = "Post Trade",
  post,
  user,
}: CommunitySharePreviewModalProps) {
  useEffect(() => {
    if (!open) return
    const prev = document.body.style.overflow
    document.body.style.overflow = "hidden"
    return () => {
      document.body.style.overflow = prev
    }
  }, [open])

  useEffect(() => {
    if (!open || submitting) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [open, onClose, submitting])

  if (!open || !post) return null

  return (
    <div
      className="fixed inset-0 z-[200] flex items-end sm:items-center justify-center bg-black/70 p-3 sm:p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="community-share-preview-title"
      onClick={() => {
        if (!submitting) onClose()
      }}
    >
      <div
        className="w-full max-w-lg max-h-[min(92vh,900px)] flex flex-col overflow-hidden rounded-xl border border-white/10 bg-[#0b1220] shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex shrink-0 items-center justify-between gap-3 border-b border-white/10 px-4 py-3">
          <div className="min-w-0">
            <h2
              id="community-share-preview-title"
              className="text-base font-semibold text-white"
            >
              Community post preview
            </h2>
            <p className="text-xs text-white/50">
              This is how your trade will appear in the feed.
            </p>
          </div>
          <button
            type="button"
            disabled={submitting}
            onClick={onClose}
            className="shrink-0 rounded-lg border border-white/10 bg-white/5 px-3 py-1.5 text-sm text-white transition hover:bg-white/10 disabled:cursor-not-allowed disabled:opacity-50"
          >
            Close
          </button>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto overflow-x-hidden p-3 sm:p-4">
          <FeedPostCard
            post={post}
            user={user}
            likeMeta={EMPTY_LIKE_META}
            comments={EMPTY_COMMENTS}
            commentSubmitting={false}
            detailOpen
            preview
            onSelectPost={() => {}}
            onToggleLike={() => {}}
            onSubmitComment={async () => false}
            onSharePost={() => {}}
          />
        </div>

        <div className="flex shrink-0 flex-col-reverse gap-2 border-t border-white/10 bg-[#0b1220] p-3 sm:flex-row sm:justify-end sm:gap-3">
          <button
            type="button"
            disabled={submitting}
            onClick={onClose}
            className="w-full rounded-lg border border-white/10 bg-white/5 px-4 py-2.5 text-sm font-medium text-white transition hover:bg-white/10 disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto"
          >
            Continue Editing
          </button>
          <button
            type="button"
            disabled={submitting}
            onClick={onPostTrade}
            className="w-full rounded-lg bg-green-500 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-green-600 disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
          >
            {submitting ? "Saving…" : postTradeLabel}
          </button>
        </div>
      </div>
    </div>
  )
}
