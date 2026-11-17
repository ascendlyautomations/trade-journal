/** supabase-js prefixes channel names before storing them on the socket. */
export const REALTIME_TOPIC_PREFIX = "realtime:"

export function realtimeChannelTopic(channelName: string): string {
  return channelName.startsWith(REALTIME_TOPIC_PREFIX)
    ? channelName
    : `${REALTIME_TOPIC_PREFIX}${channelName}`
}

export function isRealtimeChannelTopic(topic: string, channelName: string): boolean {
  return topic === realtimeChannelTopic(channelName)
}

/**
 * A remount must drop the previous channel before `.on("postgres_changes")`.
 * That call throws once the channel is already joined.
 */
export function realtimeChannelsToReplace<T extends { topic: string }>(
  channels: readonly T[],
  channelName: string
): T[] {
  return channels.filter((channel) => isRealtimeChannelTopic(channel.topic, channelName))
}
