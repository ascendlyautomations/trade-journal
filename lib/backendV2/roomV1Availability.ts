let cachedUnavailable = false

export function isRoomBootstrapRpcCachedUnavailable(): boolean {
  return cachedUnavailable
}

export function markRoomBootstrapRpcUnavailable(): void {
  cachedUnavailable = true
}

export function clearRoomBootstrapRpcUnavailableCache(): void {
  cachedUnavailable = false
}

export function __resetRoomBootstrapRpcAvailabilityForTests(): void {
  cachedUnavailable = false
}
