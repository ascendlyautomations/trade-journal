import type { PostgrestError } from "@supabase/supabase-js"

/**
 * PostgREST typed client cannot parse select strings built from shared constants
 * (embeds, dynamic joins). Call `.overrideTypes<TRow[], { merge: false }>()` at
 * the end of the chain to declare the runtime-validated projection shape.
 *
 * @see https://supabase.com/docs/reference/javascript/select — overrideTypes
 */
export type ProjectedRowsOverride<TRow> = {
  overrideTypes<NewResult, Options extends { merge?: boolean } = { merge: true }>(
    ...args: Options extends { merge: false } ? [] : never
  ): PromiseLike<{
    data: TRow[] | null
    error: PostgrestError | null
  }>
}

/** Narrow RPC/REST JSON to a plain object for decoders. */
export function asJsonObject(value: unknown): Record<string, unknown> | null {
  if (value == null || typeof value !== "object" || Array.isArray(value)) {
    return null
  }
  return value as Record<string, unknown>
}

/** Narrow RPC/REST JSON arrays for row mappers. */
export function asJsonObjectArray(value: unknown): Record<string, unknown>[] {
  if (!Array.isArray(value)) return []
  return value.filter(
    (item): item is Record<string, unknown> =>
      item != null && typeof item === "object" && !Array.isArray(item)
  )
}

/** Map projected query rows through an existing normalizer. */
export function mapProjectedRows<T>(
  data: unknown,
  map: (row: Record<string, unknown>) => T
): T[] {
  return asJsonObjectArray(data).map(map)
}
