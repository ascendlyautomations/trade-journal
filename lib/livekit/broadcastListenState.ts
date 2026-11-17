export type BroadcastListenState = {
  muted: boolean
  volume: number
}

export function defaultBroadcastListenState(): BroadcastListenState {
  return { muted: false, volume: 1 }
}

export function clampBroadcastListenVolume(value: number): number {
  if (!Number.isFinite(value)) return 1
  return Math.min(1, Math.max(0, value))
}

/** Mute changes the flag only. The slider level stays put for unmute. */
export function withBroadcastListenMuted(
  state: BroadcastListenState,
  muted: boolean
): BroadcastListenState {
  return { muted, volume: state.volume }
}

export function withBroadcastListenVolume(
  state: BroadcastListenState,
  volume: number
): BroadcastListenState {
  return { muted: state.muted, volume: clampBroadcastListenVolume(volume) }
}

/** Applied to every attached element, including tracks that subscribe later. */
export function broadcastElementListen(state: BroadcastListenState): {
  muted: boolean
  volume: number
} {
  return { muted: state.muted, volume: state.volume }
}

/**
 * One element per track. The previous node is removed before the map stores the new one.
 */
export function replaceAttachedAudioSlot<T>(
  attached: Map<string, T>,
  sid: string,
  next: T,
  removePrevious: (previous: T) => void
): void {
  const previous = attached.get(sid)
  if (previous && previous !== next) {
    removePrevious(previous)
    attached.delete(sid)
  }
  attached.set(sid, next)
}

/** iOS Safari ignores writes to HTMLMediaElement.volume and leaves it at 1. */
export function mediaElementVolumeIsAdjustable(element: { volume: number }): boolean {
  const original = element.volume
  try {
    element.volume = 0.5
    const applied = element.volume === 0.5
    element.volume = original
    return applied
  } catch {
    try {
      element.volume = original
    } catch {
      /* ignore */
    }
    return false
  }
}
