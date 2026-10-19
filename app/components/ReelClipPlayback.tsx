"use client"

import {
  forwardRef,
  useCallback,
  useEffect,
  useImperativeHandle,
  useMemo,
  useRef,
  useState,
  type Ref,
} from "react"
import ReelClipPlayOverlay from "@/app/components/ReelClipPlayOverlay"
import ReelIdlePoster from "@/app/components/ReelIdlePoster"
import { getReelPosterImageUrl } from "@/lib/reelVideo"

export type ReelClipPlaybackHandle = {
  play: () => Promise<void>
  pause: () => void
  getVideoElement: () => HTMLVideoElement | null
}

type ReelClipPlaybackProps = {
  videoUrl: string
  thumbnailUrl?: string | null
  className?: string
  videoClassName?: string
  /** Show native browser controls after playback starts. */
  nativeControls?: boolean
  muted?: boolean
  onPlayingChange?: (playing: boolean) => void
}

const ReelClipPlayback = forwardRef(function ReelClipPlayback(
  {
    videoUrl,
    thumbnailUrl,
    className = "relative mx-auto flex min-h-0 w-full max-w-sm flex-1 items-center justify-center",
    videoClassName = "max-h-[calc(100dvh-8rem)] w-full rounded-xl object-contain",
    nativeControls = false,
    muted = true,
    onPlayingChange,
  }: ReelClipPlaybackProps,
  ref: Ref<ReelClipPlaybackHandle>
) {
  const videoRef = useRef<HTMLVideoElement>(null)
  const [hasStarted, setHasStarted] = useState(false)
  const [playing, setPlaying] = useState(false)

  const imagePosterUrl = useMemo(
    () => getReelPosterImageUrl(thumbnailUrl),
    [thumbnailUrl]
  )

  const syncPlaying = useCallback(
    (next: boolean) => {
      setPlaying(next)
      onPlayingChange?.(next)
    },
    [onPlayingChange]
  )

  const releaseVideo = useCallback(() => {
    const video = videoRef.current
    if (!video) return
    video.pause()
    video.removeAttribute("src")
    video.load()
  }, [])

  const beginPlayback = useCallback(async () => {
    const video = videoRef.current
    if (!video) return
    setHasStarted(true)
    try {
      await video.play()
      syncPlaying(true)
    } catch {
      syncPlaying(false)
    }
  }, [syncPlaying])

  useImperativeHandle(ref, () => ({
    play: beginPlayback,
    pause: () => {
      videoRef.current?.pause()
      syncPlaying(false)
    },
    getVideoElement: () => videoRef.current,
  }))

  useEffect(() => {
    return () => {
      releaseVideo()
    }
  }, [releaseVideo])

  const showPoster = !playing
  const showPlayOverlay = !playing

  return (
    <div className={className}>
      <div className="relative w-full">
        <video
          ref={videoRef}
          src={videoUrl}
          poster={imagePosterUrl ?? undefined}
          className={`${videoClassName} relative z-0 block ${
            showPoster ? "opacity-0" : "opacity-100"
          }`}
          style={{ aspectRatio: "9/16" }}
          playsInline
          preload="metadata"
          muted={muted}
          controls={nativeControls && hasStarted && playing}
          onPlay={() => {
            setHasStarted(true)
            syncPlaying(true)
          }}
          onPause={() => syncPlaying(false)}
          onEnded={() => syncPlaying(false)}
        />

        {showPoster ? (
          <div
            className="absolute inset-0 z-[1] overflow-hidden"
            style={{ aspectRatio: "9/16" }}
          >
            <ReelIdlePoster
              thumbnailUrl={thumbnailUrl}
              className={`h-full w-full object-contain ${videoClassName}`}
            />
          </div>
        ) : null}

        {showPlayOverlay ? (
          <button
            type="button"
            onClick={() => void beginPlayback()}
            className="absolute inset-0 z-[2] flex items-center justify-center"
            aria-label="Play clip"
          >
            <ReelClipPlayOverlay
              buttonClassName="h-14 w-14 text-xl"
              dimClassName="bg-transparent"
            />
          </button>
        ) : null}
      </div>
    </div>
  )
})

export default ReelClipPlayback
