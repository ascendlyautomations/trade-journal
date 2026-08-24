"use client"

import dynamic from "next/dynamic"
import { useEffect, useRef, useState } from "react"
import { createPortal } from "react-dom"
import type { ReelClipPlaybackHandle } from "@/app/components/ReelClipPlayback"
import DetailModalVideo from "@/app/components/ui/DetailModalVideo"
import { ProfileAvatarImg, PROFILE_PAGE_AVATAR_PX } from "@/app/components/SafeProfileAvatar"
import type { ReelRow } from "@/lib/reels"
import { formatRelativeTime } from "@/lib/formatRelativeTime"
import { useIsNativeIos } from "@/lib/useIsNativeIos"
import {
  DETAIL_MODAL_STACKED_Z_INDEX_CLASS,
  useModalScrollLock,
  useStackedModalEscape,
} from "@/app/components/ui/modalLayout"

const NativeIosMediaViewer = dynamic(
  () => import("@/app/components/ui/NativeIosMediaViewer"),
  { ssr: false }
)

type ReelViewerProps = {
  reel: ReelRow | null
  creator?: {
    username?: string | null
    avatar_url?: string | null
    name?: string | null
  } | null
  onClose: () => void
}

function VolumeOnIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      aria-hidden
    >
      <path d="M11 5L6 9H3v6h3l5 4V5z" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M15.5 8.5a5 5 0 010 7" strokeLinecap="round" />
    </svg>
  )
}

function VolumeOffIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      aria-hidden
    >
      <path d="M11 5L6 9H3v6h3l5 4V5z" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M16 9l5 6M21 9l-5 6" strokeLinecap="round" />
    </svg>
  )
}

const controlButtonClass =
  "flex h-10 w-10 items-center justify-center rounded-full border border-white/15 bg-black/55 text-white shadow-lg backdrop-blur-sm transition hover:bg-white/15"

/** Remember last exit time per video URL so reopen continues (native iOS). */
const nativeVideoTimeByUrl = new Map<string, number>()

export default function ReelViewer({ reel, creator, onClose }: ReelViewerProps) {
  const nativeIos = useIsNativeIos()
  const playbackRef = useRef<ReelClipPlaybackHandle>(null)
  const [mounted, setMounted] = useState(false)
  const [playing, setPlaying] = useState(false)
  const [muted, setMuted] = useState(true)

  useEffect(() => {
    setMounted(true)
  }, [])

  useEffect(() => {
    if (!reel) {
      playbackRef.current?.pause()
      setPlaying(false)
      setMuted(true)
      return
    }
    if (nativeIos) return
    playbackRef.current?.pause()
    setPlaying(false)
  }, [reel, reel?.id, nativeIos])

  useModalScrollLock(Boolean(reel) && !nativeIos)
  useStackedModalEscape(Boolean(reel) && !nativeIos, onClose)

  useEffect(() => {
    const playback = playbackRef
    return () => {
      const video = playback.current?.getVideoElement()
      if (video) {
        video.pause()
        video.removeAttribute("src")
        video.load()
      }
      playback.current?.pause()
    }
  }, [])

  useEffect(() => {
    if (nativeIos) return
    const video = playbackRef.current?.getVideoElement()
    if (!video) return
    video.muted = muted
  }, [muted, reel?.id, playing, nativeIos])

  if (!reel || !mounted) return null

  const displayName =
    creator?.username?.trim() ||
    creator?.name?.trim() ||
    "Trader"

  if (nativeIos) {
    const initialTime = nativeVideoTimeByUrl.get(reel.video_url) ?? 0
    return (
      <NativeIosMediaViewer
        open
        items={[
          {
            type: "video",
            url: reel.video_url,
            poster: reel.thumbnail_url,
            initialTime,
            startMuted: true,
          },
        ]}
        onClose={onClose}
        zIndexClass={DETAIL_MODAL_STACKED_Z_INDEX_CLASS}
        onVideoTime={(url, time) => {
          nativeVideoTimeByUrl.set(url, time)
        }}
      />
    )
  }

  const toggleMute = () => {
    setMuted((prev) => !prev)
  }

  return createPortal(
    <div
      className={`fixed inset-0 ${DETAIL_MODAL_STACKED_Z_INDEX_CLASS} flex items-center justify-center bg-black/90 p-4`}
      role="presentation"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label="Clip viewer"
        className="relative flex h-full w-full max-w-md flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="absolute right-0 top-0 z-20 flex items-center gap-2 p-2 sm:p-3">
          <button
            type="button"
            onClick={toggleMute}
            className={controlButtonClass}
            aria-label={muted ? "Unmute" : "Mute"}
          >
            {muted ? (
              <VolumeOffIcon className="h-5 w-5" />
            ) : (
              <VolumeOnIcon className="h-5 w-5" />
            )}
          </button>
          <button
            type="button"
            onClick={onClose}
            className={controlButtonClass}
            aria-label="Close"
          >
            <span className="text-xl leading-none">×</span>
          </button>
        </div>

        <DetailModalVideo
          ref={playbackRef}
          src={reel.video_url}
          poster={reel.thumbnail_url}
          muted={muted}
          onPlayingChange={setPlaying}
        />

        <div className="mt-3 shrink-0 rounded-xl border border-white/10 bg-[#0b1f3a]/90 p-4 backdrop-blur-sm">
          <div className="flex items-center gap-3">
            <ProfileAvatarImg
              src={creator?.avatar_url}
              className="h-9 w-9 border border-white/10"
              displaySizePx={PROFILE_PAGE_AVATAR_PX}
            />
            <div className="min-w-0">
              <p className="truncate text-sm font-semibold text-white">
                {displayName}
              </p>
              <p className="text-xs text-gray-400">
                {formatRelativeTime(reel.created_at)}
              </p>
            </div>
          </div>
          {reel.caption?.trim() ? (
            <p className="mt-3 whitespace-pre-wrap text-sm text-gray-200">
              {reel.caption}
            </p>
          ) : null}
        </div>
      </div>
    </div>,
    document.body
  )
}
