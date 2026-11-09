import { TrackSource } from "livekit-server-sdk"

type LiveKitParticipantTrack = {
  source?: TrackSource
  muted?: boolean
}

type LiveKitParticipantSnapshot = {
  tracks?: LiveKitParticipantTrack[]
}

/** Unmuted mic tracks — best-effort when not connected to the room client-side. */
export function countSpeakingFromLiveKitParticipantInfo(
  participant: LiveKitParticipantSnapshot
): boolean {
  for (const track of participant.tracks ?? []) {
    if (track.source === TrackSource.MICROPHONE && track.muted === false) {
      return true
    }
  }
  return false
}

export function summarizeGeneralVoicePresence(
  participants: LiveKitParticipantSnapshot[]
): { connectedCount: number; speakingCount: number } {
  let speakingCount = 0
  for (const p of participants) {
    if (countSpeakingFromLiveKitParticipantInfo(p)) speakingCount += 1
  }
  return { connectedCount: participants.length, speakingCount }
}
