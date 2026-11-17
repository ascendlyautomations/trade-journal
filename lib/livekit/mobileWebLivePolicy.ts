/**
 * Pure decisions for mobile-web live voice and broadcast.
 * Kept free of LiveKit and DOM so server mute, client guards, and tests share one path.
 */

export const BROADCAST_REMOTE_AUDIO_ROOT_ID = "tradetraxs-broadcast-remote-audio"
export const LIVE_VOICE_REMOTE_AUDIO_ROOT_ID = "tradetraxs-live-voice-remote-audio"
export const BROADCAST_MEDIA_ATTR = "data-tt-broadcast-media"

/** Moderator mute must remove publish. Authorized unmute is the only restore. */
export function generalVoiceMuteAllowsPublish(muted: boolean): boolean {
  return !muted
}

/**
 * Local unmute is allowed only when the join token could publish and LiveKit
 * has not revoked `canPublish`. `undefined` means permissions have not arrived yet.
 */
export function clientMayEnableGeneralVoiceMicrophone(input: {
  joinedWithPublish: boolean
  liveKitCanPublish: boolean | undefined
}): boolean {
  if (!input.joinedWithPublish) return false
  if (input.liveKitCanPublish === false) return false
  return true
}

/** Production included: the unlock control is not a diagnostics-only affordance. */
export function shouldShowLiveVoicePlaybackUnlock(input: {
  hasSession: boolean
  canPlaybackAudio: boolean
}): boolean {
  return input.hasSession && !input.canPlaybackAudio
}

export function shouldShowBroadcastEnableSound(input: {
  isWatching: boolean
  isPublishing: boolean
  canPlaybackAudio: boolean
}): boolean {
  return input.isWatching && !input.isPublishing && !input.canPlaybackAudio
}

/**
 * Joining or leaving a conversation keeps the existing LiveKit room when it is
 * already the same broadcast, so remote playback is not torn down and re-autoplayed.
 */
export function shouldKeepBroadcastConnectionForConversation(input: {
  connected: boolean
  sameRoom: boolean
  sameSession: boolean
}): boolean {
  return input.connected && input.sameRoom && input.sameSession
}

/** Microphone publish happens only after an explicit Accept. Dismiss never enables it. */
export function speakInviteAllowsMicrophone(input: { accepted: boolean }): boolean {
  return input.accepted === true
}

type PauseCandidate = {
  closest: (selector: string) => unknown
  getAttribute: (name: string) => string | null
}

/** Skip broadcast program audio/video and the live-voice playback elements themselves. */
export function liveVoicePolicyShouldPauseMedia(element: PauseCandidate): boolean {
  if (element.getAttribute(BROADCAST_MEDIA_ATTR) === "true") return false
  if (element.closest(`#${BROADCAST_REMOTE_AUDIO_ROOT_ID}`)) return false
  if (element.closest(`#${LIVE_VOICE_REMOTE_AUDIO_ROOT_ID}`)) return false
  if (element.closest(`[${BROADCAST_MEDIA_ATTR}="true"]`)) return false
  return true
}
