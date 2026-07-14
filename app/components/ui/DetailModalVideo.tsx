"use client"

import { forwardRef, type Ref } from "react"
import ReelClipPlayback, {
  type ReelClipPlaybackHandle,
} from "@/app/components/ReelClipPlayback"
import { cn } from "./cn"

type DetailModalVideoProps = {
  src: string
  poster?: string | null
  muted?: boolean
  onPlayingChange?: (playing: boolean) => void
  /**
   * Profile reel viewer only: ~5–10% tighter max height on short screens.
   * Keeps 9:16 object-contain; large displays stay near full column height.
   */
  compactVertical?: boolean
}

/** Modal clip: poster frame until play, then native controls. */
const DetailModalVideo = forwardRef(function DetailModalVideo(
  { src, poster, muted, onPlayingChange, compactVertical = false }: DetailModalVideoProps,
  ref: Ref<ReelClipPlaybackHandle>
) {
  return (
    <ReelClipPlayback
      ref={ref}
      videoUrl={src}
      thumbnailUrl={poster}
      nativeControls
      muted={muted}
      onPlayingChange={onPlayingChange}
      className={cn(
        "relative w-full",
        compactVertical && "mx-auto flex max-w-full items-center justify-center"
      )}
      videoClassName={cn(
        "block rounded-lg object-contain",
        compactVertical
          ? "tt-profile-reel-video relative z-0 mx-auto h-auto w-auto max-w-full"
          : "w-full max-h-[60dvh] md:max-h-full md:max-w-full"
      )}
    />
  )
})

export default DetailModalVideo
