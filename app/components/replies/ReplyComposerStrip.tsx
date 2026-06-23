"use client"

import { truncateReplyPreview } from "@/lib/replyReference"

type ReplyComposerStripProps = {
  authorName: string
  preview: string
  onCancel: () => void
}

export default function ReplyComposerStrip({
  authorName,
  preview,
  onCancel,
}: ReplyComposerStripProps) {
  const clipped = truncateReplyPreview(preview)

  return (
    <div className="flex items-start gap-2 rounded-lg border-l-2 border-blue-400 bg-white/5 px-2.5 py-2 text-xs">
      <div className="min-w-0 flex-1">
        <p className="font-medium text-blue-300">Replying to {authorName}</p>
        {clipped ? (
          <p className="mt-0.5 truncate text-gray-400">&ldquo;{clipped}&rdquo;</p>
        ) : null}
      </div>
      <button
        type="button"
        onClick={onCancel}
        className="shrink-0 rounded p-1 text-gray-400 hover:bg-white/10 hover:text-white"
        aria-label="Cancel reply"
      >
        ✕
      </button>
    </div>
  )
}
