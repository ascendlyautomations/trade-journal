import type { TradingReportKind, TradingReportPeriodKey } from "./tradingReportTypes"
import { tradingReportPeriodId } from "./tradingReportPeriods"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"

export async function requestTradingReportNotification(input: {
  periodKey: TradingReportPeriodKey
  kind: TradingReportKind
  title: string
}): Promise<void> {
  try {
    const periodId = tradingReportPeriodId(input.periodKey)
    const href = `/dashboard?report=${encodeURIComponent(input.periodKey)}`
    const authHeaders = await supabaseBearerHeaders()

    await fetch("/api/trading-reports/notify", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...authHeaders,
      },
      body: JSON.stringify({
        periodKey: input.periodKey,
        periodId,
        kind: input.kind,
        title: input.title,
        href,
      }),
    })
    if (typeof window !== "undefined") {
      window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
    }
  } catch (error) {
    console.warn("[tradingReports] notification request failed", error)
  }
}
