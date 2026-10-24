"use client"

import ContentMediaPreview from "@/app/components/ContentMediaPreview"

type DetailModalImageProps = {
  src: string
  onClick?: (url: string) => void
  displayMode?: string | null
  imageCrop?: unknown
}

/** Expanded modal media. Taller than the scrolling card preview. */
export default function DetailModalImage({
  src,
  onClick,
  displayMode,
  imageCrop,
}: DetailModalImageProps) {
  return (
    <ContentMediaPreview
      src={src}
      preset="feed-detail"
      variant="detail"
      displayMode={displayMode}
      imageCrop={imageCrop}
      onClick={onClick}
    />
  )
}
