import { liveVoicePolicyShouldPauseMedia } from "../mobileWebLivePolicy.ts"

/**
 * Pause competing in-tab media when live voice connects.
 * Broadcast program audio/video is left playing, including its mute state.
 */
export function applyLiveVoiceAudioPolicyOnConnect(): void {
  if (typeof document === "undefined") return
  for (const el of document.querySelectorAll("audio,video")) {
    if (!liveVoicePolicyShouldPauseMedia(el)) continue
    try {
      ;(el as HTMLMediaElement).pause()
    } catch {
      /* ignore */
    }
  }
}
