import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "./database.types.ts"
import {
  createReadTimeoutSignal,
  supabaseResultToError,
  withServerReadRetry,
} from "./serverReadRetry.ts"

const DEFAULT_READ_TIMEOUT_MS = 20_000

/** One-shot service-role table read with timeout + transient retry. */
export async function serviceRoleTableRead<T>(
  client: SupabaseClient<Database>,
  operation: string,
  run: (signal: AbortSignal) => Promise<{ data: T | null; error: unknown }>,
  options?: { timeoutMs?: number; signal?: AbortSignal }
): Promise<T> {
  const timeoutMs = options?.timeoutMs ?? DEFAULT_READ_TIMEOUT_MS

  return withServerReadRetry(
    async () => {
      const timeout = createReadTimeoutSignal(timeoutMs, options?.signal)
      try {
        const { data, error } = await run(timeout.signal)
        const readError = supabaseResultToError(
          error as { message?: string; code?: string } | null,
          operation
        )
        if (readError) throw readError
        return data as T
      } finally {
        timeout.dispose()
      }
    },
    { operation, signal: options?.signal }
  )
}
