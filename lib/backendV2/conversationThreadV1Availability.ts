let sessionUnavailable = false

export function isConversationThreadRpcCachedUnavailable(): boolean {
  return sessionUnavailable
}

export function markConversationThreadRpcUnavailable(): void {
  sessionUnavailable = true
}

export function clearConversationThreadRpcUnavailableCache(): void {
  sessionUnavailable = false
}
