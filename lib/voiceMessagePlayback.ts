"use client"

type VoicePlaybackListener = () => void

type ActiveVoicePlayback = {
  messageId: string
  audio: HTMLAudioElement
  objectUrl: string | null
  listeners: Set<VoicePlaybackListener>
}

let active: ActiveVoicePlayback | null = null
const cache = new Map<string, string>()
const globalListeners = new Set<VoicePlaybackListener>()

function notify(activePlayback: ActiveVoicePlayback) {
  for (const listener of activePlayback.listeners) {
    listener()
  }
  for (const listener of globalListeners) {
    listener()
  }
}

function stopActive() {
  if (!active) return
  active.audio.pause()
  active.audio.src = ""
  active = null
}

async function resolveAudioObjectUrl(url: string): Promise<string> {
  const cached = cache.get(url)
  if (cached) return cached
  const response = await fetch(url)
  if (!response.ok) {
    throw new Error(`Voice download failed (${response.status})`)
  }
  const blob = await response.blob()
  const objectUrl = URL.createObjectURL(blob)
  cache.set(url, objectUrl)
  return objectUrl
}

export type VoicePlaybackSnapshot = {
  messageId: string | null
  isPlaying: boolean
  currentTime: number
  duration: number
}

export function getVoicePlaybackSnapshot(): VoicePlaybackSnapshot {
  if (!active) {
    return { messageId: null, isPlaying: false, currentTime: 0, duration: 0 }
  }
  return {
    messageId: active.messageId,
    isPlaying: !active.audio.paused && !active.audio.ended,
    currentTime: active.audio.currentTime,
    duration: Number.isFinite(active.audio.duration) ? active.audio.duration : 0,
  }
}

export function subscribeVoicePlayback(listener: VoicePlaybackListener): () => void {
  globalListeners.add(listener)
  return () => {
    globalListeners.delete(listener)
  }
}

export function stopVoicePlayback() {
  stopActive()
}

export async function toggleVoicePlayback(
  messageId: string,
  audioUrl: string,
  knownDurationSec?: number
): Promise<void> {
  if (active?.messageId === messageId) {
    if (active.audio.paused) {
      await active.audio.play()
    } else {
      active.audio.pause()
    }
    notify(active)
    return
  }

  stopActive()
  const objectUrl = await resolveAudioObjectUrl(audioUrl)
  const audio = new Audio(objectUrl)
  audio.preload = "auto"

  active = {
    messageId,
    audio,
    objectUrl,
    listeners: new Set(),
  }

  const playback = active
  audio.addEventListener("timeupdate", () => notify(playback))
  audio.addEventListener("play", () => notify(playback))
  audio.addEventListener("pause", () => notify(playback))
  audio.addEventListener("ended", () => {
    notify(playback)
    stopActive()
  })

  if (knownDurationSec && Number.isFinite(knownDurationSec)) {
    void knownDurationSec
  }

  await audio.play()
  notify(playback)
}

export function scrubVoicePlayback(messageId: string, progress: number) {
  if (!active || active.messageId !== messageId) return
  const clamped = Math.min(Math.max(progress, 0), 1)
  const duration = Number.isFinite(active.audio.duration)
    ? active.audio.duration
    : 0
  if (duration <= 0) return
  active.audio.currentTime = duration * clamped
  notify(active)
}
