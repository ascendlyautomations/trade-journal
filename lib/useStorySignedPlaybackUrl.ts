"use client"

import { useEffect, useState } from "react"
import { supabase } from "@/lib/supabaseClient"
import { createStorySignedMediaUrl } from "@/lib/storySignedMedia"
type StoryMediaLike = {
  image_url?: string | null
  storage_path?: string | null
}

export function useStorySignedPlaybackUrl(
  story: StoryMediaLike | null | undefined
): string | null {
  const [url, setUrl] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false

    const resolve = async () => {
      if (!story) {
        setUrl(null)
        return
      }
      const signed = await createStorySignedMediaUrl(supabase, story)
      if (!cancelled) {
        setUrl(signed)
      }
    }

    void resolve()
    return () => {
      cancelled = true
    }
  }, [story?.image_url, story?.storage_path])

  return url
}