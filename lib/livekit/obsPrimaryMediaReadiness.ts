import type { ParticipantInfo } from "@livekit/protocol"
import { TrackType } from "@livekit/protocol"

/**
 * True when LiveKit reports the program publisher has at least one unmuted VIDEO track.
 * Participant presence alone is insufficient: the ingress participant can join before tracks publish.
 */
export function primaryPublisherHasPublishableVideo(
  participant: ParticipantInfo | undefined | null
): boolean {
  const tracks = participant?.tracks
  if (!tracks?.length) return false
  return tracks.some((t) => t.type === TrackType.VIDEO && !t.muted)
}
