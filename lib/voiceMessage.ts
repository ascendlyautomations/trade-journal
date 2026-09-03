/** Voice message contract — mirrors native iOS (`message-audio` bucket, type `voice`). */

export const VOICE_MESSAGE_MAX_MS = 120_000
export const VOICE_MESSAGE_BUCKET = "message-audio"

export type VoiceRecordingFormat = {
  mimeType: string
  extension: string
  contentType: string
}

const MIME_CANDIDATES: VoiceRecordingFormat[] = [
  { mimeType: "audio/mp4", extension: "m4a", contentType: "audio/mp4" },
  { mimeType: "audio/aac", extension: "aac", contentType: "audio/aac" },
]

/** Prefer AAC/M4A (Safari + native iOS). When unsupported, caller uses WAV capture. */
export function pickMediaRecorderFormat(): VoiceRecordingFormat | null {
  if (typeof MediaRecorder === "undefined") return null
  for (const candidate of MIME_CANDIDATES) {
    if (MediaRecorder.isTypeSupported(candidate.mimeType)) {
      return candidate
    }
  }
  return null
}

export function formatVoiceDuration(seconds: number): string {
  const total = Math.max(0, Math.floor(seconds))
  const minutes = Math.floor(total / 60)
  const remainder = total % 60
  return `${minutes}:${String(remainder).padStart(2, "0")}`
}

export function voiceWaveformHeights(seed: string, count = 24): number[] {
  let hash = 5381
  for (let i = 0; i < seed.length; i += 1) {
    hash = (hash * 33) ^ seed.charCodeAt(i)
  }
  const heights: number[] = []
  for (let index = 0; index < count; index += 1) {
    hash = (hash * 1_103_515_245 + index) >>> 0
    const normalized = (hash % 100) / 100
    heights.push(0.25 + normalized * 0.75)
  }
  return heights
}

export function isVoiceMessage(row: {
  type?: string | null
  audio_url?: string | null
}): boolean {
  if (row.type?.toLowerCase() === "voice") return true
  const url = row.audio_url?.trim()
  return Boolean(url)
}

export function voiceDurationSeconds(
  durationMs?: number | null
): number | undefined {
  if (durationMs == null || !Number.isFinite(durationMs)) return undefined
  return Math.max(0, durationMs / 1000)
}

export function buildVoiceStoragePath(userId: string, extension: string): string {
  return `${userId}/${Date.now()}.${extension}`
}

export function buildVoicePublicUrl(path: string): string {
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL?.replace(/\/$/, "")
  return `${base}/storage/v1/object/public/${VOICE_MESSAGE_BUCKET}/${path}`
}

/** Encode mono float32 PCM chunks as 16-bit WAV (universal playback on web + iOS AVPlayer). */
export function encodeWavBlob(
  chunks: Float32Array[],
  sampleRate: number
): Blob {
  const length = chunks.reduce((sum, chunk) => sum + chunk.length, 0)
  const buffer = new ArrayBuffer(44 + length * 2)
  const view = new DataView(buffer)

  const writeString = (offset: number, value: string) => {
    for (let i = 0; i < value.length; i += 1) {
      view.setUint8(offset + i, value.charCodeAt(i))
    }
  }

  writeString(0, "RIFF")
  view.setUint32(4, 36 + length * 2, true)
  writeString(8, "WAVE")
  writeString(12, "fmt ")
  view.setUint32(16, 16, true)
  view.setUint16(20, 1, true)
  view.setUint16(22, 1, true)
  view.setUint32(24, sampleRate, true)
  view.setUint32(28, sampleRate * 2, true)
  view.setUint16(32, 2, true)
  view.setUint16(34, 16, true)
  writeString(36, "data")
  view.setUint32(40, length * 2, true)

  let offset = 44
  for (const chunk of chunks) {
    for (let i = 0; i < chunk.length; i += 1) {
      const sample = Math.max(-1, Math.min(1, chunk[i] ?? 0))
      view.setInt16(offset, sample < 0 ? sample * 0x8000 : sample * 0x7fff, true)
      offset += 2
    }
  }

  return new Blob([buffer], { type: "audio/wav" })
}

export async function uploadVoiceMessageBlob(
  supabase: import("@supabase/supabase-js").SupabaseClient,
  userId: string,
  blob: Blob,
  format: VoiceRecordingFormat
): Promise<string> {
  const path = buildVoiceStoragePath(userId, format.extension)
  const { error } = await supabase.storage
    .from(VOICE_MESSAGE_BUCKET)
    .upload(path, blob, {
      cacheControl: "31536000",
      upsert: false,
      contentType: format.contentType,
    })
  if (error) throw error
  return buildVoicePublicUrl(path)
}
