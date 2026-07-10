"use client"

import { forwardRef, type Ref } from "react"
import ReelClipPlayback, {
  type ReelClipPlaybackHandle,
} from "@/app/components/ReelClipPlayback"

type DetailModalVideoProps = {
  src: string
  poster?: string | null
}

/** Modal clip: poster frame until play, then native controls. */
const DetailModalVideo = forwardRef(function DetailModalVideo(
  { src, poster }: DetailModalVideoProps,
  ref: Ref<ReelClipPlaybackHandle>
) {
  return (
    <ReelClipPlayback
      ref={ref}
      videoUrl={src}
      thumbnailUrl={poster}
      nativeControls
      className="relative w-full"
      videoClassName="block w-full max-h-[60dvh] rounded-lg object-contain md:max-h-full md:max-w-full"
    />
  )
})

export default DetailModalVideo
