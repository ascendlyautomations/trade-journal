/** Client-side reel video validation, thumbnail capture, and storage upload. */

import type { SupabaseClient } from "@supabase/supabase-js"
import { compressImage } from "@/lib/compressImage"
import { uploadToSupabaseStorageWithProgress } from "@/lib/supabaseStorageUploadWithProgress"
import {
  createMonotonicReporter,
  mapUploadBytesToPercent,
} from "@/lib/uploadProgress/reportProgress"
import type { UploadProgressOptions } from "@/lib/uploadProgress/types"

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

/** Seek offsets tried in order — avoids all-black first frames from encoders. */
const THUMBNAIL_SEEK_CANDIDATES = [0.25, 0.1, 0.5, 1, 0.05, 2]

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

function loadVideoElement(
  video: HTMLVideoElement,
  objectUrl: string
): Promise<void> {
  return new Promise((resolve, reject) => {
    const onLoadedData = () => {
      cleanup()
      resolve()
    }
    const onError = () => {
      cleanup()
      reject(new Error("Could not read this video file."))
    }
    const cleanup = () => {
      video.removeEventListener("loadeddata", onLoadedData)
      video.removeEventListener("error", onError)
    }

    video.addEventListener("loadeddata", onLoadedData, { once: true })
    video.addEventListener("error", onError, { once: true })
    video.src = objectUrl
  })
}

function buildVideoMetadata(video: HTMLVideoElement): ReelVideoMetadata {
  const duration = Number(video.duration)
  if (!Number.isFinite(duration) || duration <= 0) {
    throw new Error("Could not read video duration.")
  }
  if (duration > REEL_MAX_DURATION_SECONDS) {
    throw new Error(REEL_DURATION_LIMIT_MESSAGE)
  }

  return {
    durationSeconds: Math.max(1, Math.round(duration)),
    width: video.videoWidth,
    height: video.videoHeight,
  }
}

export function readReelVideoMetadata(
  file: File
): Promise<ReelVideoMetadata> {
  const video = document.createElement("video")
  video.preload = "metadata"
  video.muted = true
  video.playsInline = true

  const objectUrl = URL.createObjectURL(file)

  return loadVideoElement(video, objectUrl)
    .then(() => buildVideoMetadata(video))
    .finally(() => {
      URL.revokeObjectURL(objectUrl)
      video.removeAttribute("src")
      video.load()
    })
}

function clampSeekTime(duration: number, seekSeconds: number): number {
  if (!Number.isFinite(duration) || duration <= 0) return 0
  const maxSeek = Math.max(duration - 0.05, 0)
  return Math.min(Math.max(seekSeconds, 0), maxSeek)
}

function buildSeekCandidates(duration: number, preferred?: number): number[] {
  const seeds =
    preferred != null
      ? [preferred, ...THUMBNAIL_SEEK_CANDIDATES]
      : THUMBNAIL_SEEK_CANDIDATES

  const seen = new Set<string>()
  const out: number[] = []

  for (const candidate of seeds) {
    const clamped = clampSeekTime(duration, candidate)
    const key = clamped.toFixed(3)
    if (seen.has(key)) continue
    seen.add(key)
    out.push(clamped)
  }

  return out
}

async function seekVideoTo(
  video: HTMLVideoElement,
  time: number
): Promise<void> {
  const target = clampSeekTime(video.duration, time)

  await new Promise<void>((resolve, reject) => {
    const onSeeked = () => {
      cleanup()
      resolve()
    }
    const onError = () => {
      cleanup()
      reject(new Error("Could not seek in this video."))
    }
    const cleanup = () => {
      video.removeEventListener("seeked", onSeeked)
      video.removeEventListener("error", onError)
    }

    video.addEventListener("seeked", onSeeked, { once: true })
    video.addEventListener("error", onError, { once: true })
    video.currentTime = target
  })
}

async function waitForPaintedVideoFrame(
  video: HTMLVideoElement
): Promise<void> {
  if (typeof video.requestVideoFrameCallback === "function") {
    await new Promise<void>((resolve) => {
      video.requestVideoFrameCallback(() => resolve())
    })
    return
  }

  await new Promise<void>((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
  })
}

function isMostlyBlackImageData(data: ImageData): boolean {
  const { data: pixels } = data
  if (pixels.length === 0) return true

  let darkSamples = 0
  let samples = 0

  for (let i = 0; i < pixels.length; i += 16) {
    const r = pixels[i]!
    const g = pixels[i + 1]!
    const b = pixels[i + 2]!
    const luminance = (r + g + b) / 3
    if (luminance < 20) darkSamples += 1
    samples += 1
  }

  return samples > 0 && darkSamples / samples > 0.92
}

function captureVideoFrame(
  video: HTMLVideoElement,
  metadata: ReelVideoMetadata
): Promise<{ blob: Blob; sample: ImageData } | null> {
  const width = video.videoWidth || metadata.width
  const height = video.videoHeight || metadata.height
  if (!width || !height) return Promise.resolve(null)

  const canvas = document.createElement("canvas")
  canvas.width = width
  canvas.height = height

  const ctx = canvas.getContext("2d", { willReadFrequently: true })
  if (!ctx) return Promise.resolve(null)

  ctx.drawImage(video, 0, 0, width, height)

  const sampleWidth = Math.min(width, 96)
  const sampleHeight = Math.min(height, 96)
  const sample = ctx.getImageData(0, 0, sampleWidth, sampleHeight)

  return new Promise((resolve) => {
    canvas.toBlob(
      (blob) => {
        if (!blob) {
          resolve(null)
          return
        }
        resolve({ blob, sample })
      },
      "image/jpeg",
      0.9
    )
  })
}

export async function captureReelVideoThumbnail(
  file: File,
  seekSeconds = 0.25
): Promise<{ blob: Blob; metadata: ReelVideoMetadata }> {
  const video = document.createElement("video")
  video.preload = "auto"
  video.muted = true
  video.playsInline = true

  const objectUrl = URL.createObjectURL(file)

  try {
    await loadVideoElement(video, objectUrl)
    const metadata = buildVideoMetadata(video)
    const candidates = buildSeekCandidates(video.duration, seekSeconds)

    let fallback: Blob | null = null

    for (const time of candidates) {
      await seekVideoTo(video, time)
      await waitForPaintedVideoFrame(video)

      const captured = await captureVideoFrame(video, metadata)
      if (!captured) continue

      if (!fallback) fallback = captured.blob

      if (!isMostlyBlackImageData(captured.sample)) {
        return { blob: captured.blob, metadata }
      }
    }

    if (fallback) {
      return { blob: fallback, metadata }
    }

    throw new Error("Could not generate a thumbnail.")
  } finally {
    URL.revokeObjectURL(objectUrl)
    video.removeAttribute("src")
    video.load()
  }
}

/** Local upload preview URL from a captured video frame (caller must revoke). */
export async function createReelVideoPreviewObjectUrl(
  file: File
): Promise<{ previewUrl: string; durationSeconds: number }> {
  const { blob, metadata } = await captureReelVideoThumbnail(file)
  return {
    previewUrl: URL.createObjectURL(blob),
    durationSeconds: metadata.durationSeconds,
  }
}

/** True when a reel media URL points at a video file (not a JPEG thumbnail). */
export function isReelVideoMediaUrl(url: string | null | undefined): boolean {
  const lower = String(url ?? "").trim().toLowerCase()
  if (!lower) return false
  return (
    /\.(mp4|mov|m4v)(\?|#|$)/i.test(lower) || lower.includes("/videos/")
  )
}

export function reelStoragePublicUrl(storagePath: string): string {
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return storagePath
  const normalized = storagePath.replace(/^\/+/, "")
  return `${base}/storage/v1/object/public/reels/${normalized}`
}

/** Extract storage object path from a public reels bucket URL. */
export function reelPublicUrlToStoragePath(publicUrl: string): string | null {
  const raw = String(publicUrl ?? "").trim()
  if (!raw) return null
  const marker = "/storage/v1/object/public/reels/"
  const idx = raw.indexOf(marker)
  if (idx < 0) return null
  try {
    return decodeURIComponent(raw.slice(idx + marker.length))
  } catch {
    return raw.slice(idx + marker.length)
  }
}

export async function uploadReelVideoFile(
  supabase: SupabaseClient,
  userId: string,
  file: File,
  options?: UploadProgressOptions
): Promise<{ publicUrl: string; storagePath: string } | { error: string }> {
  const storagePath = `${userId}/videos/${Date.now()}-${file.name.replace(/\s+/g, "-")}`
  const report = createMonotonicReporter(options?.onProgress)

  if (options?.onProgress) {
    report({ percent: 5, stage: "Uploading video…" })
    const { error } = await uploadToSupabaseStorageWithProgress(supabase, {
      bucket: "reels",
      path: storagePath,
      file,
      contentType: file.type || "video/mp4",
      onProgress: (loaded, total) => {
        report({
          percent: mapUploadBytesToPercent(loaded, total, {
            start: 8,
            end: 88,
          }),
          stage: "Uploading video…",
        })
      },
    })
    if (error) return { error }
  } else {
    const { error } = await supabase.storage
      .from("reels")
      .upload(storagePath, file, {
        contentType: file.type || "video/mp4",
        upsert: false,
      })

    if (error) {
      return { error: error.message }
    }
  }

  return {
    storagePath,
    publicUrl: reelStoragePublicUrl(storagePath),
  }
}

export async function uploadReelThumbnailBlob(
  supabase: SupabaseClient,
  userId: string,
  blob: Blob,
  options?: UploadProgressOptions
): Promise<{ publicUrl: string; storagePath: string } | { error: string }> {
  const rawFile = new File([blob], "thumbnail.jpg", { type: "image/jpeg" })
  const report = createMonotonicReporter(options?.onProgress)
  report({ percent: 90, stage: "Saving thumbnail…" })
  const uploadFile = await compressImage(rawFile)
  const storagePath = `${userId}/thumbnails/${Date.now()}-thumb.jpg`

  if (options?.onProgress) {
    const { error } = await uploadToSupabaseStorageWithProgress(supabase, {
      bucket: "reels",
      path: storagePath,
      file: uploadFile,
      contentType: uploadFile.type || "image/jpeg",
      onProgress: (loaded, total) => {
        report({
          percent: mapUploadBytesToPercent(loaded, total, {
            start: 90,
            end: 96,
          }),
          stage: "Saving thumbnail…",
        })
      },
    })
    if (error) return { error }
  } else {
    const { error } = await supabase.storage
      .from("reels")
      .upload(storagePath, uploadFile, {
        contentType: uploadFile.type || "image/jpeg",
        upsert: false,
      })

    if (error) {
      return { error: error.message }
    }
  }

  return {
    storagePath,
    publicUrl: reelStoragePublicUrl(storagePath),
  }
}
