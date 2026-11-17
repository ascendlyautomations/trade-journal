/** Clip media yields while LiveKit voice or a livestream is using audio. */
export function clipPlaybackBlockedByLiveKit(input: {
  liveVoiceActive: boolean
  broadcastActive: boolean
}): boolean {
  return input.liveVoiceActive || input.broadcastActive
}
