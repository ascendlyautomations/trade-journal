"use client"

import ContentMediaPreview from "@/app/components/ContentMediaPreview"

type DetailModalImageProps = {
  src: string
  onClick?: (url: string) => void
  displayMode?: string | null
}

/** Expanded modal media. Taller than the scrolling card preview. */
export default function DetailModalImage({
  src,
  onClick,
  displayMode,
}: DetailModalImageProps) {
  return (
    <ContentMediaPreview
      src={src}
      preset="feed-detail"
      variant="detail"
      displayMode={displayMode}
      onClick={onClick}
    />
  )
}
