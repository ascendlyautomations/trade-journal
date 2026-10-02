import { NextResponse } from "next/server"
import {
  parseProLimitPayload,
  proLimitKindFromError,
  type ProLimitKind,
} from "@/lib/proGateReason"

/** Map Supabase/Postgres limit errors to the shared BFF contract. */
export function proLimitResponseFromError(
  error: unknown,
  status = 403
): NextResponse | null {
  const payload = parseProLimitPayload(error)
  if (!payload) return null
  return NextResponse.json(payload, { status })
}

export { proLimitKindFromError }
