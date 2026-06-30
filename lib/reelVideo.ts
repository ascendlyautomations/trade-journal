/** Client-side reel video validation, thumbnail capture, and storage upload. */

import type { SupabaseClient } from "@supabase/supabase-js"
import { compressImage } from "@/lib/compressImage"

export const REEL_MAX_DURATION_SECONDS = 90
export const REEL_MAX_FILE_BYTES = 100 * 1024 * 1024

/** User-facing duration limit copy (keep in sync across validation + UI). */
export const REEL_MAX_DURATION_LABEL = "1 min 30 sec"
export const REEL_DURATION_LIMIT_MESSAGE =
  "Reels must be 90 seconds (1 minute 30 seconds) or less."

const ACCEPTED_VIDEO_MIME_TYPES = new Set([
  "video/mp4",
  "video/quicktime",
  "video/x-m4v",
])

const ACCEPTED_VIDEO_EXTENSIONS = new Set([".mp4", ".mov", ".m4v"])

export type ReelVideoValidationError = {
  title: string
  message: string
}

export type ReelVideoMetadata = {
  durationSeconds: number
  width: number
  height: number
}

function fileExtension(name: string): string {
  const idx = name.lastIndexOf(".")
  if (idx < 0) return ""
  return name.slice(idx).toLowerCase()
}

export function isAcceptedReelVideoFile(file: File): boolean {
  const mime = file.type?.toLowerCase() ?? ""
  if (mime && ACCEPTED_VIDEO_MIME_TYPES.has(mime)) return true
  return ACCEPTED_VIDEO_EXTENSIONS.has(fileExtension(file.name))
}

export function validateReelVideoFile(file: File): ReelVideoValidationError | null {
  if (!file) {
    return {
      title: "No Video Selected",
      message: "Choose an MP4 or MOV video to continue.",
    }
  }

  if (!isAcceptedReelVideoFile(file)) {
    return {
      title: "Unsupported Format",
      message: "Reels support MP4 and MOV videos only.",
    }
  }

  if (file.size > REEL_MAX_FILE_BYTES) {
    return {
      title: "File Too Large",
      message: "Videos must be 100 MB or smaller.",
    }
  }

  return null
}

export function readReelVideoMetadata(
  file: File
): Promise<ReelVideoMetadata> {
  return new Promise((resolve, reject) => {
    const video = document.createElement("video")
    video.preload = "metadata"
    video.muted = true
    video.playsInline = true

    const objectUrl = URL.createObjectURL(file)

    const cleanup = () => {
      URL.revokeObjectURL(objectUrl)
      video.removeAttribute("src")
      video.load()
    }

    video.onloadedmetadata = () => {
      const duration = Number(video.duration)
      if (!Number.isFinite(duration) || duration <= 0) {
        cleanup()
        reject(new Error("Could not read video duration."))
        return
      }

      if (duration > REEL_MAX_DURATION_SECONDS) {
        cleanup()
        reject(new Error(REEL_DURATION_LIMIT_MESSAGE))
        return
      }

      resolve({
        durationSeconds: Math.max(1, Math.round(duration)),
        width: video.videoWidth,
        height: video.videoHeight,
      })
    }

    video.onerror = () => {
      cleanup()
      reject(new Error("Could not read this video file."))
    }

    video.src = objectUrl
  })
}

export async function captureReelVideoThumbnail(
  file: File,
  seekSeconds = 0.25
): Promise<{ blob: Blob; metadata: ReelVideoMetadata }> {
  const metadata = await readReelVideoMetadata(file)

  return new Promise((resolve, reject) => {
    const video = document.createElement("video")
    video.preload = "auto"
    video.muted = true
    video.playsInline = true

    const objectUrl = URL.createObjectURL(file)

    const cleanup = () => {
      URL.revokeObjectURL(objectUrl)
      video.removeAttribute("src")
      video.load()
    }

    video.onloadedmetadata = () => {
      const target = Math.min(
        Math.max(seekSeconds, 0),
        Math.max(metadata.durationSeconds - 0.1, 0)
      )
      video.currentTime = target
    }

    video.onseeked = () => {
      const canvas = document.createElement("canvas")
      canvas.width = video.videoWidth || metadata.width
      canvas.height = video.videoHeight || metadata.height

      const ctx = canvas.getContext("2d")
      if (!ctx) {
        cleanup()
        reject(new Error("Could not generate a thumbnail."))
        return
      }

      ctx.drawImage(video, 0, 0, canvas.width, canvas.height)
      canvas.toBlob(
        (blob) => {
          cleanup()
          if (!blob) {
            reject(new Error("Could not generate a thumbnail."))
            return
          }
          resolve({ blob, metadata })
        },
        "image/jpeg",
        0.9
      )
    }

    video.onerror = () => {
      cleanup()
      reject(new Error("Could not generate a thumbnail from this video."))
    }

    video.src = objectUrl
  })
}

export function reelStoragePublicUrl(storagePath: string): string {
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return storagePath
  const normalized = storagePath.replace(/^\/+/, "")
  return `${base}/storage/v1/object/public/reels/${normalized}`
}

export async function uploadReelVideoFile(
  supabase: SupabaseClient,
  userId: string,
  file: File
): Promise<{ publicUrl: string; storagePath: string } | { error: string }> {
  const storagePath = `${userId}/videos/${Date.now()}-${file.name.replace(/\s+/g, "-")}`

  const { error } = await supabase.storage
    .from("reels")
    .upload(storagePath, file, {
      contentType: file.type || "video/mp4",
      upsert: false,
    })

  if (error) {
    return { error: error.message }
  }

  return {
    storagePath,
    publicUrl: reelStoragePublicUrl(storagePath),
  }
}

export async function uploadReelThumbnailBlob(
  supabase: SupabaseClient,
  userId: string,
  blob: Blob
): Promise<{ publicUrl: string; storagePath: string } | { error: string }> {
  const rawFile = new File([blob], "thumbnail.jpg", { type: "image/jpeg" })
  const uploadFile = await compressImage(rawFile)
  const storagePath = `${userId}/thumbnails/${Date.now()}-thumb.jpg`

  const { error } = await supabase.storage
    .from("reels")
    .upload(storagePath, uploadFile, {
      contentType: uploadFile.type || "image/jpeg",
      upsert: false,
    })

  if (error) {
    return { error: error.message }
  }

  return {
    storagePath,
    publicUrl: reelStoragePublicUrl(storagePath),
  }
}
