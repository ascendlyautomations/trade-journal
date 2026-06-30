"use client"

import { forwardRef, type Ref } from "react"

type DetailModalVideoProps = {
  src: string
  poster?: string | null
}

/** Modal reel video: stacked on mobile, fill left panel on md+. */
const DetailModalVideo = forwardRef(function DetailModalVideo(
  { src, poster }: DetailModalVideoProps,
  ref: Ref<HTMLVideoElement>
) {
  return (
    <video
      ref={ref}
      src={src}
      poster={poster ?? undefined}
      className="block w-full max-h-[60dvh] rounded-lg bg-black/30 object-contain md:max-h-full md:max-w-full md:bg-transparent"
      style={{ aspectRatio: "9/16" }}
      playsInline
      controls
      preload="metadata"
    />
  )
})

export default DetailModalVideo
