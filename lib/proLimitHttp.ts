import { NextResponse } from "next/server"
import {
  buildProLimitPayload,
  type ProLimitKind,
} from "./proGateReason"

export { buildProLimitPayload as proLimitJsonBody, isProLimitResponseBody } from "./proGateReason"

/** Structured JSON for BFF/API routes — clients should read `code` + `limit`. */
export function proLimitJsonResponse(limit: ProLimitKind, status = 403) {
  return NextResponse.json(buildProLimitPayload(limit), { status })
}
