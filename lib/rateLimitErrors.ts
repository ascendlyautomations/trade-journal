export function isRateLimitExceededError(message: string | undefined | null): boolean {
  return Boolean(message?.includes("rate_limit_exceeded"))
}

export function formatRateLimitExceededMessage(fallback: string): string {
  return fallback
}
