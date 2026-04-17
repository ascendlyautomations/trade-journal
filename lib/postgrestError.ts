import type { PostgrestError } from "@supabase/supabase-js"

/**
 * PGRST116 — JSON object requested, multiple (or fewer) rows returned.
 * Often seen with `.single()` when count ≠ 1; treat as empty / non-fatal for optional reads.
 */
export function isPostgrestRowCardinalityError(e: PostgrestError): boolean {
  return e.code === "PGRST116"
}

/** Full PostgREST details in development builds for faster debugging. */
export function formatPostgrestErrorMessage(e: PostgrestError): string {
  if (process.env.NODE_ENV !== "development") return e.message
  return [e.message, e.details, e.hint, e.code && `(${e.code})`].filter(Boolean).join(" | ")
}

/** Logs the full Supabase/PostgREST error shape (dev only). */
export function logPostgrestErrorDev(context: string, error: PostgrestError): void {
  if (process.env.NODE_ENV === "production") return
  console.error(`[TradeTrax] ${context}`, {
    message: error.message,
    code: error.code,
    details: error.details,
    hint: error.hint,
  })
}
