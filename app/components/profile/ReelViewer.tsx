"use client"

import { useEffect, useRef, useState } from "react"
import { createPortal } from "react-dom"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import type { ReelRow } from "@/lib/reels"
import { formatRelativeTime } from "@/lib/formatRelativeTime"

type ReelViewerProps = {
  reel: ReelRow | null
  creator?: {
    username?: string | null
    avatar_url?: string | null
    name?: string | null
  } | null
  onClose: () => void
}

function PlayIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M8 5v14l11-7z" />
    </svg>
  )
}

function PauseIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M6 5h4v14H6V5zm8 0h4v14h-4V5z" />
    </svg>
  )
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

export default function ReelViewer({ reel, creator, onClose }: ReelViewerProps) {
  const videoRef = useRef<HTMLVideoElement>(null)
  const [mounted, setMounted] = useState(false)
  const [playing, setPlaying] = useState(false)
  const [muted, setMuted] = useState(true)

  useEffect(() => {
    setMounted(true)
  }, [])

  useEffect(() => {
    if (!reel) {
      setPlaying(false)
      setMuted(true)
    }
  }, [reel])

  useEffect(() => {
    if (!reel) return
    const prev = document.body.style.overflow
    document.body.style.overflow = "hidden"
    return () => {
      document.body.style.overflow = prev
    }
  }, [reel])

  useEffect(() => {
    if (!reel) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [reel, onClose])

  useEffect(() => {
    const video = videoRef.current
    if (!video || !reel) return
    video.pause()
    video.currentTime = 0
    setPlaying(false)
  }, [reel?.id])

  if (!reel || !mounted) return null

  const displayName =
    creator?.username?.trim() ||
    creator?.name?.trim() ||
    "Trader"

  const togglePlay = () => {
    const video = videoRef.current
    if (!video) return
    if (video.paused) {
      void video.play()
      setPlaying(true)
    } else {
      video.pause()
      setPlaying(false)
    }
  }

  const toggleMute = () => {
    const video = videoRef.current
    if (!video) return
    const next = !muted
    video.muted = next
    setMuted(next)
  }

  return createPortal(
    <div
      className="fixed inset-0 z-[10060] flex items-center justify-center bg-black/90 p-4"
      role="presentation"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label="Reel viewer"
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

        <div className="relative mx-auto flex min-h-0 w-full max-w-sm flex-1 items-center justify-center">
          <video
            ref={videoRef}
            src={reel.video_url}
            poster={reel.thumbnail_url}
            className="max-h-[calc(100dvh-8rem)] w-full rounded-xl object-contain"
            playsInline
            preload="none"
            muted={muted}
            onPlay={() => setPlaying(true)}
            onPause={() => setPlaying(false)}
            onEnded={() => setPlaying(false)}
          />

          <button
            type="button"
            onClick={togglePlay}
            className="absolute inset-0 flex items-center justify-center"
            aria-label={playing ? "Pause" : "Play"}
          >
            {!playing ? (
              <span className={`${controlButtonClass} h-14 w-14`}>
                <PlayIcon className="h-7 w-7" />
              </span>
            ) : null}
          </button>
        </div>

        <div className="mt-3 shrink-0 rounded-xl border border-white/10 bg-[#0b1f3a]/90 p-4 backdrop-blur-sm">
          <div className="flex items-center gap-3">
            <ProfileAvatarImg
              src={creator?.avatar_url}
              className="h-9 w-9 border border-white/10"
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
