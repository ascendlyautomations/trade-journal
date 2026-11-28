"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import { supabase } from "@/lib/supabaseClient"
import {
  fetchOwnerStoryArchive,
  type ArchivedStoryRow,
} from "@/lib/storyMediaAccess"
import { createStorySignedMediaUrl } from "@/lib/storySignedMedia"
import { storyMediaIsVideo } from "@/lib/activeStories"
import { deleteStoryById } from "@/lib/activeStories"
import StoryFrame from "@/app/components/feed/StoryFrame"
import type { StoryBarProfile } from "@/app/components/feed/FeedStoriesBar"
import { useUserProfile } from "@/lib/useUserProfile"

export default function StoryArchiveHome() {
  const { profile } = useUserProfile()
  const [rows, setRows] = useState<ArchivedStoryRow[]>([])
  const [loading, setLoading] = useState(true)
  const [openStory, setOpenStory] = useState<ArchivedStoryRow | null>(null)
  const [playbackUrl, setPlaybackUrl] = useState<string | null>(null)
  const [thumbUrls, setThumbUrls] = useState<Record<string, string>>({})

  const barProfile: StoryBarProfile | null = useMemo(() => {
    if (!profile?.id) return null
    return {
      id: String(profile.id),
      username: profile.username ?? "User",
      avatar_url: profile.avatar_url ?? null,
    }
  }, [profile])

  const loadArchive = useCallback(async () => {
    setLoading(true)
    try {
      const items = await fetchOwnerStoryArchive(supabase, 120, 0)
      setRows(items)
      const nextThumbs: Record<string, string> = {}
      await Promise.all(
        items.map(async (row) => {
          const signed = await createStorySignedMediaUrl(supabase, row)
          if (signed) nextThumbs[row.id] = signed
        })
      )
      setThumbUrls(nextThumbs)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void loadArchive()
  }, [loadArchive])

  const openViewer = useCallback(async (story: ArchivedStoryRow) => {
    const signed = await createStorySignedMediaUrl(supabase, story)
    if (!signed) return
    setPlaybackUrl(signed)
    setOpenStory(story)
  }, [])

  const handleDelete = useCallback(async () => {
    if (!openStory) return
    const { error } = await deleteStoryById(supabase, openStory.id)
    if (error) return
    setOpenStory(null)
    setPlaybackUrl(null)
    await loadArchive()
  }, [loadArchive, openStory])

  if (loading) {
    return <p className="text-sm text-gray-400">Loading story archive…</p>
  }

  if (rows.length === 0) {
    return (
      <p className="text-sm text-gray-400">
        Expired stories you have not deleted will appear here.
      </p>
    )
  }

  return (
    <div className="space-y-4">
      <p className="text-sm text-gray-400">
        Stories older than 24 hours. Only you can view these.
      </p>
      <div className="grid grid-cols-3 gap-2 sm:grid-cols-4 md:grid-cols-5">
        {rows.map((row) => {
          const thumb = thumbUrls[row.id]
          const isVideo = storyMediaIsVideo(
            row.resolved_storage_path ?? row.storage_path ?? row.image_url
          )
          return (
            <button
              key={row.id}
              type="button"
              className="relative aspect-[9/16] overflow-hidden rounded-lg bg-white/10 ring-1 ring-white/15"
              onClick={() => void openViewer(row)}
            >
              {thumb ? (
                isVideo ? (
                  <video
                    src={thumb}
                    className="h-full w-full object-cover"
                    muted
                    playsInline
                    preload="metadata"
                  />
                ) : (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={thumb}
                    alt=""
                    className="h-full w-full object-cover"
                    draggable={false}
                  />
                )
              ) : (
                <span className="flex h-full items-center justify-center text-xs text-gray-500">
                  …
                </span>
              )}
            </button>
          )
        })}
      </div>

      {openStory && playbackUrl && barProfile ? (
        <div className="fixed inset-0 z-[80] bg-black/90">
          <StoryFrame
            profile={barProfile}
            imageUrl={playbackUrl}
            timestamp={openStory.created_at}
            className="h-full w-full"
            priority
            headerRight={
              <button
                type="button"
                onClick={handleDelete}
                className="rounded-md bg-red-500/90 px-3 py-1 text-xs font-semibold text-white"
              >
                Delete
              </button>
            }
          />
          <button
            type="button"
            className="absolute bottom-6 left-1/2 -translate-x-1/2 rounded-full bg-white/15 px-4 py-2 text-sm text-white"
            onClick={() => {
              setOpenStory(null)
              setPlaybackUrl(null)
            }}
          >
            Close
          </button>
        </div>
      ) : null}
    </div>
  )
}