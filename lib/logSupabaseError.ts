export type SupabaseErrorShape = {
  code?: string
  message?: string
  details?: string
  hint?: string
}

/** Logs PostgREST errors with all fields (plain console.error(err) often prints `{}`). */
export function logSupabaseError(
  action: string,
  error: SupabaseErrorShape | null | undefined,
  meta?: Record<string, unknown>
): void {
  console.error(`[supabase] ${action}`, {
    ...meta,
    code: error?.code,
    message: error?.message,
    details: error?.details,
    hint: error?.hint,
    error,
  })
}
