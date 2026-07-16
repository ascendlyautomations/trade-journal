"use client"

import CommunitySharePreviewPanel from "@/app/components/CommunitySharePreviewPanel"
import ModalCloseButton from "@/app/components/ui/ModalCloseButton"
import {
  useModalScrollLock,
  useStackedModalEscape,
} from "@/app/components/ui/modalLayout"

type CommunitySharePreviewModalProps = {
  open: boolean
  onClose: () => void
  onPostTrade: () => void
  submitting?: boolean
  postTradeDisabled?: boolean
  title?: string
  subtitle?: string
  postTradeLabel?: string
  submittingLabel?: string
  post: Record<string, unknown> | null
  user: { id: string } | null
}

/**
 * Stacked above ScrollableModalShell (z-10050) / Quick Trade, below FeedbackModal (z-10060).
 * Escape / outside-click close only this layer — parent trade modals stay open underneath.
 */
export const COMMUNITY_SHARE_PREVIEW_Z_INDEX_CLASS = "z-[10055]"

export default function CommunitySharePreviewModal({
  open,
  onClose,
  onPostTrade,
  submitting = false,
  postTradeDisabled = false,
  title = "Preview Post",
  subtitle = "This is how your trade will appear in the feed.",
  postTradeLabel = "Post Trade",
  submittingLabel = "Saving…",
  post,
  user,
}: CommunitySharePreviewModalProps) {
  useModalScrollLock(open)
  useStackedModalEscape(open && !submitting, onClose)

  if (!open || !post) return null

  return (
    <div
      className={`fixed inset-0 ${COMMUNITY_SHARE_PREVIEW_Z_INDEX_CLASS} flex items-end justify-center bg-black/70 p-3 sm:items-center sm:p-4`}
      role="dialog"
      aria-modal="true"
      aria-labelledby="community-share-preview-title"
      onClick={() => {
        if (!submitting) onClose()
      }}
    >
      <div
        className="w-full max-w-lg max-h-[min(90dvh,calc(100dvh-2rem))] flex flex-col overflow-hidden rounded-xl border border-white/10 bg-[#0b1220] shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex shrink-0 items-center justify-between gap-3 border-b border-white/10 px-4 py-3">
          <div className="min-w-0">
            <h2
              id="community-share-preview-title"
              className="text-base font-semibold text-white"
            >
              {title}
            </h2>
            <p className="text-xs text-gray-400">
              {subtitle}
            </p>
          </div>
          <ModalCloseButton onClick={onClose} disabled={submitting} />
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto overflow-x-hidden p-3 sm:p-4">
          <CommunitySharePreviewPanel post={post} user={user} showHeading={false} />
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
            disabled={submitting || postTradeDisabled}
            onClick={onPostTrade}
            className="w-full rounded-lg bg-blue-500 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto disabled:hover:bg-blue-500"
          >
            {submitting ? submittingLabel : postTradeLabel}
          </button>
        </div>
      </div>
    </div>
  )
}
