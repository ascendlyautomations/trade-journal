export const TRADING_REPORT_PUSH_STATUSES = [
  "pending",
  "sent",
  "no_tokens",
  "failed",
  "skipped",
] as const

export type TradingReportPushStatus =
  (typeof TRADING_REPORT_PUSH_STATUSES)[number]

export function readTradingReportPushStatus(
  content: string | null | undefined
): TradingReportPushStatus {
  if (!content?.trim()) return "pending"
  try {
    const parsed = JSON.parse(content) as {
      pushDelivery?: { status?: string }
    }
    const status = parsed.pushDelivery?.status
    if (
      status === "pending" ||
      status === "sent" ||
      status === "no_tokens" ||
      status === "failed" ||
      status === "skipped"
    ) {
      return status
    }
  } catch {
    return "pending"
  }
  return "pending"
}

/** A saved notification row is not proof the push reached a device. */
export function tradingReportPushNeedsRetry(
  status: TradingReportPushStatus
): boolean {
  return status === "pending" || status === "failed" || status === "no_tokens"
}

export function writeTradingReportPushStatus(
  content: string,
  status: TradingReportPushStatus,
  at = new Date()
): string {
  const parsed = JSON.parse(content) as Record<string, unknown>
  parsed.pushDelivery = { status, at: at.toISOString() }
  return JSON.stringify(parsed)
}
