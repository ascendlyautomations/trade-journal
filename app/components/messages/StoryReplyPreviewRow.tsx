"use client"

import { useEffect, useState } from "react"
import { supabase } from "@/lib/supabaseClient"
import {
  fetchStoryDmMediaAccess,
  resolveStoryPlaybackUrl,
} from "@/lib/storyMediaAccess"
import { storyMediaIsVideo } from "@/lib/activeStories"
import { PhotoIcon, PlayIcon } from "@heroicons/react/24/solid"

type Props = {
  storyId: string
  isMe: boolean
  contextLabel: string
  onOpenStory?: (storyId: string) => void
  onMediaLoad?: () => void
}

export default function StoryReplyPreviewRow({
  storyId,
  isMe,
  contextLabel,
  onOpenStory,
  onMediaLoad,
}: Props) {
  const [playbackUrl, setPlaybackUrl] = useState<string | null>(null)
  const [allowed, setAllowed] = useState(false)
  const [checked, setChecked] = useState(false)

  useEffect(() => {
    let cancelled = false
    void (async () => {
      const access = await fetchStoryDmMediaAccess(supabase, storyId)
      if (cancelled) return
      setAllowed(access.allowed)
      if (access.allowed) {
        const url = await resolveStoryPlaybackUrl(supabase, access)
        if (!cancelled) {
          setPlaybackUrl(url)
          onMediaLoad?.()
        }
      }
      setChecked(true)
    })()
    return () => {
      cancelled = true
    }
  }, [onMediaLoad, storyId])

  if (!checked) {
    return (
      <div className="flex items-center gap-2 border-b border-white/10 px-3 py-2">
        <div className="h-10 w-10 shrink-0 rounded-md bg-white/10" />
        <p className="min-w-0 text-xs font-medium text-gray-400">{contextLabel}</p>
      </div>
    )
  }

  if (!allowed) {
    return (
      <div className="flex items-center gap-2 border-b border-white/10 px-3 py-2">
        <PhotoIcon className="h-5 w-5 shrink-0 text-gray-500" aria-hidden />
        <p className="min-w-0 text-xs font-medium text-gray-400">Story unavailable</p>
      </div>
    )
  }

  const isVideo = playbackUrl ? storyMediaIsVideo(playbackUrl) : false
  const thumb = playbackUrl ? (
    isVideo ? (
      <video
        src={playbackUrl}
        className="h-10 w-10 shrink-0 rounded-md object-cover ring-1 ring-white/15"
        muted
        playsInline
        preload="metadata"
      />
    ) : (
      // eslint-disable-next-line @next/next/no-img-element
      <img
        src={playbackUrl}
        alt=""
        className="h-10 w-10 shrink-0 rounded-md object-cover ring-1 ring-white/15"
        draggable={false}
        onLoad={onMediaLoad}
      />
    )
  ) : (
    <div className="h-10 w-10 shrink-0 rounded-md bg-white/10" />
  )

  return (
    <button
      type="button"
      className="flex w-full items-center gap-2 border-b border-white/10 px-3 py-2 text-left transition hover:bg-white/5"
      onClick={(event) => {
        event.stopPropagation()
        if (allowed) onOpenStory?.(storyId)
      }}
    >
      {thumb}
      {isVideo ? (
        <PlayIcon className="h-4 w-4 shrink-0 text-gray-400" aria-hidden />
      ) : null}
      <p className="min-w-0 flex-1 text-xs font-medium text-gray-400">{contextLabel}</p>
    </button>
  )
}