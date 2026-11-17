"use client"

import ContentMediaPreview from "@/app/components/ContentMediaPreview"
import LinkedClipImageOverlay from "@/app/components/trade/LinkedClipImageOverlay"
import ReelThumbnailPreview from "@/app/components/ReelThumbnailPreview"
import type { ReelRow } from "@/lib/reels"

type TradeDetailMediaWithClipOverlayProps = {
  imageSrc: string | null
  displayMode?: string | null
  imageCrop?: unknown
  attachedReel?: ReelRow | null
  onOpenImage?: (url: string) => void
  onOpenClip?: () => void
  imageClassName?: string
}

export default function TradeDetailMediaWithClipOverlay({
  imageSrc,
  displayMode,
  imageCrop,
  attachedReel,
  onOpenImage,
  onOpenClip,
  imageClassName = "block w-full overflow-hidden rounded-[14px]",
}: TradeDetailMediaWithClipOverlayProps) {
  if (!imageSrc && !attachedReel) return null

  if (imageSrc) {
    return (
      <div className="relative w-full">
        <ContentMediaPreview
          src={imageSrc}
          preset="feed-detail"
          displayMode={displayMode}
          imageCrop={imageCrop}
          onClick={onOpenImage}
          className={imageClassName}
        />
        {attachedReel && onOpenClip ? (
          <div className="pointer-events-none absolute inset-0">
            <div className="pointer-events-auto absolute bottom-2.5 right-2.5 z-10 sm:bottom-3.5 sm:right-3.5">
              <LinkedClipImageOverlay
                onClick={(e) => {
                  e.stopPropagation()
                  onOpenClip()
                }}
              />
            </div>
          </div>
        ) : null}
      </div>
    )
  }

  if (attachedReel && onOpenClip) {
    return (
      <ReelThumbnailPreview
        reel={attachedReel}
        onClick={onOpenClip}
        maxWidthClass="max-w-[min(100%,340px)]"
        showDuration={false}
      />
    )
  }

  return null
}
