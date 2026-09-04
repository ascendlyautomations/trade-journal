"use client"

import StorageImage from "@/app/components/ui/StorageImage"
import {
  storyShareCardTitle,
  type StorySharePayload,
} from "@/lib/storyShareMessage"

type StoryShareMessageCardProps = {
  payload: StorySharePayload
  isOutgoing?: boolean
  onViewStory?: (storyId: string) => void
  onMediaLoad?: () => void
  className?: string
}

export default function StoryShareMessageCard({
  payload,
  isOutgoing = false,
  onViewStory,
  onMediaLoad,
  className = "",
}: StoryShareMessageCardProps) {
  const imageUrl = payload.story_image_url?.trim() ?? ""
  const title = storyShareCardTitle(payload)

  return (
    <div
      className={`overflow-hidden rounded-2xl border border-white/10 bg-[#1e293b] shadow-lg shadow-black/20 ${
        isOutgoing ? "rounded-br-md" : "rounded-bl-md"
      } ${className}`.trim()}
    >
      <div className="flex items-center gap-3 p-3">
        {imageUrl ? (
          <StorageImage
            src={imageUrl}
            originalSrc={imageUrl}
            preset="message-story-thumb"
            fallbackToOriginal={false}
            alt=""
            className="h-12 w-12 shrink-0 rounded-md object-cover ring-1 ring-white/15"
            draggable={false}
            onLoad={onMediaLoad}
            onError={onMediaLoad}
          />
        ) : (
          <div
            className="h-12 w-12 shrink-0 rounded-md bg-white/10 ring-1 ring-white/15"
            aria-hidden
          />
        )}
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-semibold text-gray-100">{title}</p>
          <button
            type="button"
            onClick={(event) => {
              event.stopPropagation()
              onViewStory?.(payload.story_id)
            }}
            className="mt-0.5 text-xs font-medium text-blue-300 transition hover:text-blue-200"
          >
            View Story
          </button>
        </div>
      </div>
    </div>
  )
}
