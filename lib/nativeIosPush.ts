/**
 * Legacy Capacitor push/badge API surface — no-ops after Capacitor removal.
 * Native APNs registration lives in `native-ios/` + `/api/push/*`.
 */

export function isNativeIosPushBridgeReady(): boolean {
  return false
}

export async function setNativeIosBadgeCount(_count: number): Promise<void> {
  // no-op
}

export async function registerNativeIosPush(_opts?: {
  userId?: string
}): Promise<void> {
  // no-op — Capacitor push abandoned
}

export async function unregisterNativeIosPush(_opts?: {
  allDevices?: boolean
  deviceToken?: string | null
}): Promise<void> {
  // no-op
}
