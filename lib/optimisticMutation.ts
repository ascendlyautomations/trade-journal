/**
 * Shared optimistic mutation helper.
 * Apply UI immediately, run the existing mutation, rollback on failure.
 * Unique-violation (23505) is treated as success (idempotent sync).
 */

export const UNIQUE_VIOLATION = "23505"

export function isUniqueViolation(error: unknown): boolean {
  if (!error || typeof error !== "object") return false
  const code = (error as { code?: string }).code
  return code === UNIQUE_VIOLATION
}

export type OptimisticMutationResult<T = void> = {
  ok: boolean
  data?: T
  error?: unknown
  conflict?: boolean
}

export async function runOptimisticMutation<T = void>(params: {
  apply: () => void
  rollback: () => void
  mutate: () => Promise<OptimisticMutationResult<T>>
  isBenignConflict?: (error: unknown) => boolean
}): Promise<OptimisticMutationResult<T>> {
  const isBenign = params.isBenignConflict ?? isUniqueViolation

  params.apply()

  try {
    const result = await params.mutate()
    if (result.ok) return result

    if (result.error && isBenign(result.error)) {
      return { ok: true, conflict: true, data: result.data }
    }

    params.rollback()
    return result
  } catch (error) {
    params.rollback()
    return { ok: false, error }
  }
}

/** Snapshot helper for like-style { liked, count } meta. */
export type LikeMeta = { count: number; liked: boolean }

export function nextLikeMeta(meta: LikeMeta): LikeMeta {
  return meta.liked
    ? { count: Math.max(0, meta.count - 1), liked: false }
    : { count: meta.count + 1, liked: true }
}

export function likeMetaAfterConflict(meta: LikeMeta): LikeMeta {
  return {
    count: Math.max(meta.count, 1),
    liked: true,
  }
}

/** Generate a client-side temp id for optimistic rows. */
export function createOptimisticTempId(prefix = "temp"): string {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
    return `${prefix}-${crypto.randomUUID()}`
  }
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`
}
