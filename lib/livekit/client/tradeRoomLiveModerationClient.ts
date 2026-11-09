"use client"

import { requestLiveKitMemberDisconnect } from "@/lib/livekit/requestLiveKitMemberDisconnect.ts"

export async function disconnectMemberFromGeneralVoice(options: {
  roomId: string
  userId: string
  accessToken: string
}): Promise<{ ok: boolean; error?: string }> {
  try {
    const res = await fetch("/api/livekit/disconnect-member", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${options.accessToken}`,
      },
      body: JSON.stringify({
        roomId: options.roomId,
        userId: options.userId,
        scope: "voice",
      }),
    })
    const payload = (await res.json().catch(() => ({}))) as { error?: string }
    if (!res.ok) {
      return { ok: false, error: payload.error || "Could not disconnect member." }
    }
    return { ok: true }
  } catch {
    return { ok: false, error: "Could not disconnect member." }
  }
}

export async function muteGeneralVoiceParticipant(options: {
  roomId: string
  targetUserId: string
  accessToken: string
  muted?: boolean
}): Promise<{ ok: boolean; error?: string }> {
  try {
    const res = await fetch("/api/livekit/voice/mute", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${options.accessToken}`,
      },
      body: JSON.stringify({
        roomId: options.roomId,
        targetUserId: options.targetUserId,
        muted: options.muted !== false,
      }),
    })
    const payload = (await res.json().catch(() => ({}))) as { error?: string }
    if (!res.ok) {
      return { ok: false, error: payload.error || "Could not mute participant." }
    }
    return { ok: true }
  } catch {
    return { ok: false, error: "Could not mute participant." }
  }
}

export async function promoteStageSpeaker(options: {
  roomId: string
  targetUserId: string
  accessToken: string
}): Promise<{ ok: boolean; error?: string }> {
  try {
    const res = await fetch("/api/livekit/stage/promote", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${options.accessToken}`,
      },
      body: JSON.stringify({
        roomId: options.roomId,
        targetUserId: options.targetUserId,
      }),
    })
    const payload = (await res.json().catch(() => ({}))) as { error?: string }
    if (!res.ok) {
      return { ok: false, error: payload.error || "Could not promote speaker." }
    }
    return { ok: true }
  } catch {
    return { ok: false, error: "Could not promote speaker." }
  }
}

export async function demoteStageSpeaker(options: {
  roomId: string
  targetUserId: string
  accessToken: string
}): Promise<{ ok: boolean; error?: string }> {
  try {
    const res = await fetch("/api/livekit/stage/demote", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${options.accessToken}`,
      },
      body: JSON.stringify({
        roomId: options.roomId,
        targetUserId: options.targetUserId,
      }),
    })
    const payload = (await res.json().catch(() => ({}))) as { error?: string }
    if (!res.ok) {
      return { ok: false, error: payload.error || "Could not demote speaker." }
    }
    return { ok: true }
  } catch {
    return { ok: false, error: "Could not demote speaker." }
  }
}

export { requestLiveKitMemberDisconnect }
