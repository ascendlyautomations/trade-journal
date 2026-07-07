import { USER_FACING_ERROR_MESSAGES } from "@/lib/userFacingError"

export function isRateLimitExceededError(message: string | undefined | null): boolean {
  return Boolean(message?.toLowerCase().includes("rate_limit_exceeded"))
}

export function formatRateLimitExceededMessage(_fallback?: string): string {
  return USER_FACING_ERROR_MESSAGES.RATE_LIMIT_EXCEEDED
}
