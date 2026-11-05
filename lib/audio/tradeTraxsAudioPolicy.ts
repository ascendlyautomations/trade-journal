/**
 * Central audio coordination policy (web + native clients).
 *
 * Live voice uses LiveKit-managed AVAudioSession on iOS; other consumers must
 * yield when a live voice session is active so categories do not fight.
 */

export type TradeTraxsAudioConsumer =
  | "livekit_voice"
  | "voice_note_record"
  | "voice_note_playback"
  | "feed_video"

/** Higher number wins when two consumers want the session at once. */
export const TRADETRAXS_AUDIO_PRIORITY: Record<TradeTraxsAudioConsumer, number> =
  {
    livekit_voice: 100,
    voice_note_record: 60,
    voice_note_playback: 40,
    feed_video: 30,
  }

export function audioConsumerMayStart(
  incoming: TradeTraxsAudioConsumer,
  active: TradeTraxsAudioConsumer | null
): boolean {
  if (!active) return true
  return (
    TRADETRAXS_AUDIO_PRIORITY[incoming] >=
    TRADETRAXS_AUDIO_PRIORITY[active]
  )
}

/** Consumers that must stop when live voice connects. */
export function consumersPreemptedByLiveVoice(): TradeTraxsAudioConsumer[] {
  return ["voice_note_record", "voice_note_playback", "feed_video"]
}
