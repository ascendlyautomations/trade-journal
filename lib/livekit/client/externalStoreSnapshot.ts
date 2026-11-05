/** Helpers for useSyncExternalStore: stable getSnapshot until publish. */

export type ExternalStoreSnapshotCache<T> = {
  getSnapshot: () => T
  publish: (build: () => T) => void
}

export function createExternalStoreSnapshotCache<T>(
  build: () => T
): ExternalStoreSnapshotCache<T> {
  let snapshot = build()
  return {
    getSnapshot: () => snapshot,
    publish: (nextBuild) => {
      snapshot = nextBuild()
    },
  }
}
