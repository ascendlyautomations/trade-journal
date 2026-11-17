/**
 * One in-memory load of trading preferences, overrides, and revisions.
 * Simultaneous callers share the in-flight request. A later load reuses the
 * result until Trading Rules are saved, which bumps the generation so the
 * next load refetches (including the revision row the save trigger inserts).
 */
export function createTradingPreferenceBundleCache<T>() {
  const cache = new Map<string, T>()
  const inflight = new Map<string, Promise<T>>()
  const generation = new Map<string, number>()

  return {
    invalidate(userId: string) {
      const id = userId.trim()
      if (!id) return
      generation.set(id, (generation.get(id) ?? 0) + 1)
      cache.delete(id)
      inflight.delete(id)
    },
    load(userId: string, fetchBundle: () => Promise<T>): Promise<T> {
      const id = userId.trim()
      const cached = cache.get(id)
      if (cached) return Promise.resolve(cached)
      const pending = inflight.get(id)
      if (pending) return pending
      const gen = generation.get(id) ?? 0
      const task = fetchBundle()
        .then((bundle) => {
          if ((generation.get(id) ?? 0) === gen) cache.set(id, bundle)
          return bundle
        })
        .finally(() => {
          if (inflight.get(id) === task) inflight.delete(id)
        })
      inflight.set(id, task)
      return task
    },
    reset() {
      cache.clear()
      inflight.clear()
      generation.clear()
    },
  }
}
