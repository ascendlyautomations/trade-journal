import { consumersPreemptedByLiveVoice } from "@/lib/audio/tradeTraxsAudioPolicy.ts"

/** Pause competing in-tab media when live voice connects (web). */
export function applyLiveVoiceAudioPolicyOnConnect(): void {
  if (typeof document === "undefined") return
  for (const el of document.querySelectorAll("audio,video")) {
    const media = el as HTMLMediaElement
    try {
      media.pause()
    } catch {
      /* ignore */
    }
  }
  void consumersPreemptedByLiveVoice
}
