/** Voice message contract — mirrors native iOS (`message-audio` bucket, type `voice`). */

import { voiceWebLog } from "./voiceWebLog"

export const VOICE_MESSAGE_MAX_MS = 120_000
export const VOICE_MESSAGE_BUCKET = "message-audio"

export type VoiceRecordingFormat = {
  mimeType: string
  extension: string
  contentType: string
}

const MIME_CANDIDATES: VoiceRecordingFormat[] = [
  {
    mimeType: "audio/mp4;codecs=mp4a.40.2",
    extension: "m4a",
    contentType: "audio/mp4",
  },
  { mimeType: "audio/mp4", extension: "m4a", contentType: "audio/mp4" },
  { mimeType: "audio/aac", extension: "aac", contentType: "audio/aac" },
]

/**
 * Safari MediaRecorder AAC/MP4 aligns with native iOS (m4a). Chromium often advertises
 * `audio/mp4` but produces containers iOS AVPlayer treats as silent — use WAV there.
 */
export function isLikelySafariVoiceRecorder(): boolean {
  if (typeof navigator === "undefined") return false
  const ua = navigator.userAgent
  return (
    /Safari\//i.test(ua) &&
    !/Chrome|Chromium|CriOS|Edg|OPR|Firefox|FxiOS/i.test(ua)
  )
}

/** Prefer AAC/M4A on Safari. Other browsers use WAV capture (see useVoiceRecorder). */
export function pickMediaRecorderFormat(): VoiceRecordingFormat | null {
  if (typeof MediaRecorder === "undefined") return null
  if (!isLikelySafariVoiceRecorder()) return null
  for (const candidate of MIME_CANDIDATES) {
    if (MediaRecorder.isTypeSupported(candidate.mimeType)) {
      return {
        mimeType: candidate.mimeType,
        extension: candidate.extension,
        contentType: candidate.contentType,
      }
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

  voiceWebLog.wavEncoded({
    fileBytes: buffer.byteLength,
    riffChunkSize: 36 + length * 2,
    pcmSampleCount: length,
    sampleRate,
    dataChunkBytes: length * 2,
    fmtChannels: 1,
    fmtBitsPerSample: 16,
    riffHeaderValid: true,
    waveHeaderValid: true,
  })

  return new Blob([buffer], { type: "audio/wav" })
}

/** Validates the uploaded blob matches the encoder header (same bytes as upload). */
export async function inspectWavBlobForUpload(blob: Blob): Promise<void> {
  if (blob.type && blob.type !== "audio/wav") return
  const buffer = await blob.arrayBuffer()
  if (buffer.byteLength < 44) {
    voiceWebLog.wavUploadInspect({
      fileBytes: buffer.byteLength,
      riffHeaderValid: false,
      waveHeaderValid: false,
      encodedPeak: null,
    })
    return
  }
  const view = new DataView(buffer)
  const riff =
    view.getUint8(0) === 0x52 &&
    view.getUint8(1) === 0x49 &&
    view.getUint8(2) === 0x46 &&
    view.getUint8(3) === 0x46
  const wave =
    view.getUint8(8) === 0x57 &&
    view.getUint8(9) === 0x41 &&
    view.getUint8(10) === 0x56 &&
    view.getUint8(11) === 0x45
  const encodedPeak = await measureEncodedAudioPeak(blob)
  voiceWebLog.wavUploadInspect({
    fileBytes: buffer.byteLength,
    riffHeaderValid: riff,
    waveHeaderValid: wave,
    riffChunkSize: riff ? view.getUint32(4, true) : null,
    fmtSampleRate: wave ? view.getUint32(24, true) : null,
    fmtChannels: wave ? view.getUint16(22, true) : null,
    fmtBitsPerSample: wave ? view.getUint16(34, true) : null,
    dataChunkBytes: wave ? view.getUint32(40, true) : null,
    encodedPeak,
  })
}

export async function uploadVoiceMessageBlob(
  supabase: import("@supabase/supabase-js").SupabaseClient,
  userId: string,
  blob: Blob,
  format: VoiceRecordingFormat
): Promise<string> {
  if (format.extension === "wav") {
    await inspectWavBlobForUpload(blob)
  }
  voiceWebLog.uploadStarted(blob.size, format.contentType)
  const path = buildVoiceStoragePath(userId, format.extension)
  const { error } = await supabase.storage
    .from(VOICE_MESSAGE_BUCKET)
    .upload(path, blob, {
      cacheControl: "31536000",
      upsert: false,
      contentType: format.contentType,
    })
  if (error) throw error
  voiceWebLog.uploadCompleted(path)
  const publicUrl = buildVoicePublicUrl(path)
  voiceWebLog.messageCreated(publicUrl)
  return publicUrl
}

/** Peak sample magnitude for PCM chunks (0–1). */
export function measurePcmPeak(chunks: Float32Array[]): number {
  let peak = 0
  for (const chunk of chunks) {
    for (let i = 0; i < chunk.length; i += 1) {
      peak = Math.max(peak, Math.abs(chunk[i] ?? 0))
    }
  }
  return peak
}

const MIN_PCM_PEAK = 0.002

export function pcmChunksLookSilent(chunks: Float32Array[]): boolean {
  if (chunks.length === 0) return true
  return measurePcmPeak(chunks) < MIN_PCM_PEAK
}

/** Decode blob in browser and measure peak — validates audible content before upload. */
export async function measureEncodedAudioPeak(blob: Blob): Promise<number | null> {
  if (typeof AudioContext === "undefined") return null
  const context = new AudioContext()
  try {
    if (context.state === "suspended") {
      await context.resume()
    }
    const buffer = await blob.arrayBuffer()
    const decoded = await context.decodeAudioData(buffer.slice(0))
    let peak = 0
    for (let channel = 0; channel < decoded.numberOfChannels; channel += 1) {
      const data = decoded.getChannelData(channel)
      for (let i = 0; i < data.length; i += 1) {
        peak = Math.max(peak, Math.abs(data[i] ?? 0))
      }
    }
    return peak
  } catch {
    return null
  } finally {
    void context.close()
  }
}

export async function logLocalPlaybackMetadata(
  blob: Blob,
  peak: number | null
): Promise<void> {
  if (typeof document === "undefined") {
    voiceWebLog.localPlaybackReady(null, peak)
    return
  }
  const url = URL.createObjectURL(blob)
  try {
    const duration = await new Promise<number | null>((resolve) => {
      const audio = document.createElement("audio")
      audio.preload = "auto"
      audio.onloadedmetadata = () => {
        resolve(Number.isFinite(audio.duration) ? audio.duration : null)
      }
      audio.onerror = () => resolve(null)
      audio.src = url
      audio.load()
    })
    voiceWebLog.localPlaybackReady(duration, peak)
  } finally {
    URL.revokeObjectURL(url)
  }
}
